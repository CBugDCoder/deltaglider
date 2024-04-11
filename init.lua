-- pull some often used (and unlikely to be overriden)
-- functions to local scope
local math_abs = math.abs
local math_cos = math.cos
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_pi = math.pi
local math_pi2 = 2 * math_pi
local math_sin = math.sin
local math_sqrt = math.sqrt
local vector_multiply = vector.multiply
local vector_new = vector.new
local vector_zero = vector.zero

-- global table for exposed functions
glider = {
	version = 20240411.182102,
}

local has_areas = minetest.get_modpath("areas")
local has_hangglider = minetest.get_modpath("hangglider")
local has_player_monoids = minetest.get_modpath("player_monoids")
local has_tnt = minetest.get_modpath("tnt")
	or minetest.get_modpath("mcl_mobitems")

local enable_flak = has_areas and minetest.settings:get_bool(
	"glider.enable_flak", true)

local flak_warning_time = tonumber(minetest.settings:get(
	"glider.flak_warning_time")) or 2

local glider_uses = tonumber(minetest.settings:get(
	"glider.uses")) or 250

local mouse_controls = minetest.settings:get_bool(
	"glider.mouse_controls", true)

local use_rockets = has_tnt and minetest.settings:get_bool(
	"glider.use_rockets", true)

local rocket_delay = math_min(65000, math_max(1,
	tonumber(minetest.settings:get("glider.rocket_delay") or 10)))

glider.rocket_delay = rocket_delay

local glider_wear = 0 < glider_uses and (65535 / glider_uses) or nil

local flak_warning = "You have entered restricted airspace!\n"
	.. "You will be shot down in " .. flak_warning_time
	.. " seconds by anti-aircraft guns!"

-- only register chatcommand if [hangglider] isn't available
if enable_flak and not has_hangglider then
	minetest.register_chatcommand("area_flak", {
		params = "<ID>",
		description = "Toggle airspace restrictions for area <ID>",
		func = function(name, param)
			local id = tonumber(param)
			if not id then
				return false, "Invalid usage, see /help area_flak."
			end

			if not areas:isAreaOwner(id, name) then
				return false, "Area " .. id
					.. " does not exist or is not owned by you."
			end

			local open = not areas.areas[id].flak
			-- Save false as nil to avoid inflating the DB.
			areas.areas[id].flak = open or nil
			areas:save()
			return true, "Area " .. id .. " airspace "
				.. (open and "closed" or "opened")
		end
	})
end

local function set_physics_overrides(player, overrides)
	if has_player_monoids then
		for name, value in pairs(overrides) do
			player_monoids[name]:add_change(
				player, value, "glider:glider")
		end
	else
		player:set_physics_override(overrides)
	end
end

local function remove_physics_overrides(player)
	for _, name in pairs({ "jump", "speed", "gravity" }) do
		if has_player_monoids then
			player_monoids[name]:del_change(
				player, "glider:glider")
		else
			player:set_physics_override({ [name] = 1 })
		end
	end
end

-- expose so other mods can override/hook-into
-- to disallow flying in certain areas or materials
-- such as on the moon or without priv in certain area
-- pos: (vector) position of player
-- name: (string) player's name
-- in_flight: (bool) is already airborne
function glider.allowed_to_fly(pos, name, in_flight) --luacheck: no unused args
	return true
end

local function friendly_airspace(pos, name)
	if not enable_flak then
		return true
	end

	local flak = false
	local owners = {}
	for _, area in pairs(areas:getAreasAtPos(pos)) do
		if area.flak then
			flak = true
		end
		owners[area.owner] = true
	end
	if flak and not owners[name] then
		return false
	end

	return true
end

local function shoot_flak_sound(pos)
	minetest.sound_play("glider_flak_shot", {
		pos = pos,
		max_hear_distance = 30,
		gain = 10.0,
	}, true)
end

local function equip_sound(pos)
	minetest.sound_play("glider_equip", {
		pos = pos,
		max_hear_distance = 8,
		gain = 1.0,
	}, true)
end

local function rot_to_dir(rot)
	return vector_new(
		-math_cos(rot.x) * math_sin(rot.y),
		math_sin(rot.x),
		math_cos(rot.x) * math_cos(rot.y)
	)
end

local function get_pitch_lift(y)
	return -(1964 / 1755 * y * y * y * y)
		- (2549 / 3510 * y * y * y)
		+ (2591 / 7020 * y * y) + (2594 / 3510 * y) + 0.75
end

local wear_hp_factor = 65535 * 0.0375 -- 3/80 == 1/20*.75
local function damage_glider(driver, luaent, crash_damage)
	if not glider_wear then
		return
	end

	local index = luaent.wield_index
	local inv = driver:get_inventory()
	local stack = inv:get_stack("main", index)
	if stack:to_string() ~= luaent.tool_string then
		local index_alt
		index, stack = nil, nil
		for i, is in ipairs(inv:get_list("main")) do
			if is:get_name() == "glider:glider" then
				index_alt = i
			end
			if is:to_string() == luaent.tool_string then
				index = i
				break
			end
		end
		index = index or index_alt
		if index then
			stack = inv:get_stack("main", index)
		end
	end
	if stack then
		stack:add_wear(crash_damage * wear_hp_factor)
		inv:set_stack("main", index, stack)
	end
end

local on_step = function(self, dtime, moveresult)
	local driver = minetest.get_player_by_name(self.driver)
	if not driver then
		-- driver logged off
		self.object:remove()
		return
	end

	self.time_from_last_rocket = math_min(
		self.time_from_last_rocket + dtime, rocket_delay)

	local vel = self.object:get_velocity()
	local speed = self.speed
	local rot = self.object:get_rotation()
	local pos = self.object:get_pos()

	-- Check surroundings
	local land = false
	local crash_speed = 0
	if moveresult and moveresult.collisions and moveresult.collides then
		for _ ,collision in pairs(moveresult.collisions) do
			land = true
			crash_speed = math_abs(crash_speed
				+ collision.old_velocity.x
				- collision.new_velocity.x
				+ collision.old_velocity.y
				- collision.new_velocity.y
				+ collision.old_velocity.z
				- collision.new_velocity.z)
		end
	end

	if land then
		local crash_damage = math_floor(math_max(crash_speed - 5, 0))
		if crash_damage > 0 then
			local node = minetest.get_node(pos)
			if minetest.registered_nodes[node.name].liquidtype == "none" then
				-- damage glider first
				damage_glider(driver, self, crash_damage)
				-- hurt player
				local hp = driver:get_hp()
				driver:set_hp(hp - crash_damage, { type = "fall" })
			end
		end
	elseif not friendly_airspace(pos, self.driver) then
		if not self.flak_timer then
			self.flak_timer = 0
			shoot_flak_sound(pos)
			minetest.chat_send_player(self.driver, flak_warning)
		else
			self.flak_timer = self.flak_timer + dtime
		end
		if self.flak_timer > flak_warning_time then
			driver:set_hp(1, {
				type = "set_hp", cause = "glider:flak"
			})
			driver:get_inventory():remove_item(
				"main", ItemStack("glider:glider"))

			shoot_flak_sound(pos)
			land = true
		end
	elseif not glider.allowed_to_fly(pos, self.driver, true) then
		land = true
	end

	if land then
		driver:set_detach()
		driver:set_eye_offset(vector_zero(), vector_zero())
		remove_physics_overrides(driver)
		driver:add_velocity(vel)
		self.object:remove()
		equip_sound(pos)
		return
	end

	if mouse_controls then
		rot.x = rot.x + (-driver:get_look_vertical() - rot.x) * dtime * 2
		local hor = driver:get_look_horizontal()
		local angle = hor - rot.y
		if angle < -math_pi then
			angle = angle + math_pi2
		elseif angle > math_pi then
			angle = angle - math_pi2
		end
		rot.y = rot.y + angle * dtime * 2
		speed = speed - math_abs(angle * dtime)
		rot.z = -angle
	else
		local control = driver:get_player_control()
		if control.up and not control.down then
			rot.x = rot.x + dtime
		elseif control.down and not control.up then
			rot.x = rot.x - dtime
		end
		if control.left and not control.right then
			rot.z = rot.z - 2 * dtime
		elseif control.right and not control.left then
			rot.z = rot.z + 2 * dtime
		end

		if rot.z ~= 0 then
			speed = speed - math_abs(rot.z * dtime)
			if math_abs(rot.z) < 0.01 then
				rot.z = 0
			end
			rot.y = rot.y - rot.z * dtime
			rot.z = rot.z - rot.z * dtime
		end
	end

	speed = math_min(math_max((speed - (rot.x ^ 3) * 4 * dtime)
		- speed * 0.01 * dtime, 2), 30)

	self.object:set_rotation(rot)
	local dir = rot_to_dir(rot)
	local lift = speed * 0.5 * get_pitch_lift(dir.y)
		* (1 - (math_abs(rot.z / math_pi)))

	local vertical_acc = lift - 5
	self.grav_speed = math_min(math_max(self.grav_speed
		+ vertical_acc * dtime, -10), 1)

	dir = vector_new(
		dir.x * speed,
		dir.y * speed + self.grav_speed,
		dir.z * speed
	)
	self.speed = speed
	self.object:set_velocity(dir)
end

local on_use = function(itemstack, driver, pt) --luacheck: no unused args
	if type(driver) ~= "userdata" then
		return  -- Real players only
	end

	local name = driver:get_player_name()
	local pos = driver:get_pos()
	local attach = driver:get_attach()
	local luaent, vel
	if attach then
		luaent = attach:get_luaentity()
		if luaent.name == "glider:hangglider" then
			vel = attach:get_velocity()
			attach:remove()
			driver:set_detach()
			driver:set_eye_offset(vector_zero(), vector_zero())
			remove_physics_overrides(driver)
			driver:add_velocity(vel)
			equip_sound(pos)
		end
	else
		if not glider.allowed_to_fly(pos, name, false) then
			return
		end

		pos.y = pos.y + 1.5
		local ent = minetest.add_entity(pos, "glider:hangglider")
		if not ent then
			-- failed to create entity -> abort
			return
		end

		luaent = ent:get_luaentity()
		luaent.driver = name
		local rot = vector_new(
			-driver:get_look_vertical(),
			driver:get_look_horizontal(),
			0
		)
		ent:set_rotation(rot)
		vel = vector_multiply(driver:get_velocity(), 2)
		ent:set_velocity(vel)
		luaent.speed = math_sqrt(vel.x ^ 2 + (vel.y * 0.25) ^ 2 + vel.z ^ 2)
		driver:set_attach(ent, "", vector_new(0, 0, -10),
			vector_new(90, 0, 0))

		driver:set_eye_offset(vector_new(0, -16.25, 0),
			vector_new(0, -15, 0))

		set_physics_overrides(driver, { jump = 0, gravity = 0.25 })
		local color = itemstack:get_meta():get("hangglider_color")
		if color then
			ent:set_properties({
				textures = { "wool_white.png^[multiply:#" .. color }
			})
		end
		if glider_wear then
			itemstack:add_wear(glider_wear)
			luaent.wield_index = driver:get_wield_index()
			luaent.tool_string = itemstack:to_string()
		end
		equip_sound(pos)
		return itemstack
	end
end


minetest.register_entity("glider:hangglider", {
	physical = true,
	pointable = false,
	visual = "mesh",
	mesh = "glider_hangglider.obj",
	textures = { "glider_hangglider.png" },
	static_save = false,
	--Functions
	on_step = on_step,
	grav_speed = 0,
	driver = "",
	free_fall = false,
	speed = 0,
	time_from_last_rocket = rocket_delay,
})

minetest.register_tool("glider:glider", {
	description = "Delta Glider",
	inventory_image = "glider_glider.png",
	on_use = on_use,
})

local mp = minetest.get_modpath("glider")
dofile(mp .. "/crafts.lua")
if use_rockets then
	dofile(mp .. "/rocket.lua")
end

minetest.register_on_dieplayer(function(player)
	remove_physics_overrides(player)
end)

minetest.register_on_leaveplayer(function(player)
	remove_physics_overrides(player)
end)

print("[glider] loaded with"
	.. (use_rockets and " " or "out ") .. "rockets.")

