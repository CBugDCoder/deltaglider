
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
	version = 20240418.142741,
}

local has_areas = minetest.get_modpath("areas")
local has_hangglider = minetest.get_modpath("hangglider")
local has_player_monoids = minetest.get_modpath("player_monoids")
local has_priv_protector = minetest.get_modpath("priv_protector")
	and minetest.global_exists("priv_protector")
	and priv_protector.get_area_priv

local has_tnt = minetest.get_modpath("tnt")
	or minetest.get_modpath("mcl_mobitems")

local has_xp_redo = minetest.get_modpath("xp_redo")
	and minetest.global_exists("xp_redo")
	and xp_redo.get_area_xp_limits and xp_redo.get_xp

local enable_flak = has_areas and minetest.settings:get_bool(
	"glider.enable_flak", true)

local flak_warning_time = tonumber(minetest.settings:get(
	"glider.flak_warning_time")) or 2

local glider_uses = tonumber(minetest.settings:get(
	"glider.uses")) or 250

local crash_damage_wear_factor = tonumber(
	minetest.settings:get("glider.crash_damage_wear_factor"))
	or 2457.5625

local max_speed = math_max(2, math_min(65535, tonumber(
	minetest.settings:get("glider.max_speed")) or 30))

local mouse_controls = minetest.settings:get_bool(
	"glider.mouse_controls", true)

local keyboard_controls = minetest.settings:get_bool(
	"glider.keyboard_controls", true)

assert(mouse_controls or keyboard_controls,
	"Neither mouse nor keyboard controls enabled.")

local use_rockets = has_tnt and minetest.settings:get_bool(
	"glider.use_rockets", true)

local rocket_cooldown = math_min(65000, math_max(1,
	tonumber(minetest.settings:get("glider.rocket_cooldown")) or 10))

glider.rocket_cooldown = rocket_cooldown

local glider_wear = 0 < glider_uses and (65535 / glider_uses) or nil

glider.allow_hangglider_while_gliding = minetest.settings:get_bool(
	"glider.allow_hangglider_while_gliding", true)

glider.allow_while_hanggliding = minetest.settings:get_bool(
	"glider.allow_while_hanggliding", false)

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

-- Allow other mods to register custom flight checks
-- to disallow flying in certain areas or materials
-- such as on the moon or without priv in certain area
-- The function's signature is: (name, driver, luaent)
-- name: (string) player's name
-- driver: (PlayerObjRef) the player object
-- luaent: (nil or luaentity) the glider luaentity. When set,
--   player is already flying. When not, player would like to
--   take off.
-- The function *must* return true to indicate that player may
-- *not* fly. A second return value of int may be provided to
-- indicate damage to player from which damage to glider
-- is also applied. Sensible values are from -20 to 20.
-- Negative meaning healing.
local grounded_checks = {}
function glider.register_grounded_check(func)
	grounded_checks[#grounded_checks + 1] = func
end

local function custom_grounded_checks(name, driver, luaent)
	local is_grounded = false
	local damage = 0
	local i = #grounded_checks
	if i == 0 then
		return is_grounded, damage
	end

	local res_bool, res_int
	repeat
		res_bool, res_int = grounded_checks[i](name, driver, luaent)
		if res_bool then
			is_grounded = true
		end
		if type(res_int) == "number" then
			damage = damage + math_max(-20, math_min(20, res_int))
		end
		i = i - 1
	until i == 0
	return is_grounded, damage
end

local function friendly_airspace(pos, name, xp, privs)
	if not enable_flak then
		return true
	end

	local flak, open = false, false
	local priv_excemption, xp_limit = false, false
	local areas_list = areas:getAreasAtPos(pos)
	local xp_area, priv_area
	local owners = {}
	for id, area in pairs(areas_list) do
		-- open areas are friendly airspace(?)
		if area.open then
			open = true
		end
		if privs then
			priv_area = priv_protector.get_area_priv(id)
			if privs[priv_area] then
				priv_excemption = true
			end
		end
		if xp then
			xp_area = xp_redo.get_area_xp_limits(id)
			if xp_area then
				if (xp_area.min and xp < xp_area.min)
					or (xp_area.max and xp > xp_area.max)
				then
					xp_limit = true
				end
			end
		end
		if area.flak then
			flak = true
		end
		owners[area.owner] = true
	end
	-- none of the areas has FLAK set -> friendly
	-- any of the overlapping areas is open -> friendly
	-- owners of overlapping areas -> safe
	if not flak or open or owners[name] then
		return true
	end

	-- privilaged players -> safe
	if privs and priv_excemption then
		return true
	end

	-- xp limits -> unfriendly
	if xp and not xp_limit then
		return true
	end

	return false
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

local function player_controls(driver)
	local meta = driver:get_meta()
	local pro = 1 == meta:get_int("glider.pro")
	if mouse_controls and keyboard_controls then
		return 0 == meta:get_int("glider.keyC"), pro
	else
		return mouse_controls, pro
	end
end

local huds = {}
local rad2deg = 180 / math_pi
local function update_hud(name, driver, rot, rocket_time, speed, vV)
	local info = ""
	if rot then
		-- glider in use
		local pitch = math_floor((10 * rot.x * rad2deg) + 0.5) * 0.1

		local heading = math_floor((10 * rot.y * rad2deg) + 0.5) * 0.1

		local sign = 0 == vV and "=" or (0 < vV and "+" or "-")
		info = "pitch: " .. pitch .. "°"
			.. " heading: " .. heading .. "°"
			.. "\n"
			.. " vV: " .. sign .. math_floor(10 * math_abs(vV) + 0.5) * 0.1
			.. " alt: " .. math_floor(driver:get_pos().y + 0.5)
			.. " v: " .. math_floor(speed + 0.5)
			.. (0 < rocket_time
				and ("\n" .. math_floor(rocket_time + 0.5)) or "")
	end

	if huds[name] then
		driver:hud_change(huds[name], "text", info)
		return
	end

	huds[name] = driver:hud_add({
		hud_elem_type = "text",
		position  = {x = 0.5, y = 0.8},
		offset    = {x = 0, y = 0},
		text      = info,
		alignment = 0,
		scale     = { x = 300, y = 90},
		number    = 0xFFFFFF,
	})
end

local function damage_driver(driver, damage)
	driver:set_hp(driver:get_hp() - damage, { type = "fall" })
end

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
		stack:add_wear(crash_damage * crash_damage_wear_factor)
		inv:set_stack("main", index, stack)
	end
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

local on_step = function(self, dtime, moveresult)
	local driver = self.object:get_children()[1]
	if not driver then
		-- driver logged off or dead
		self.object:remove()
		return
	end

	if not glider.allow_hangglider_while_gliding then
		local luaent
		for _, obj in ipairs(driver:get_children()) do
			luaent = obj:get_luaentity()
			if luaent and luaent.name == "hangglider:glider" then
				damage_glider(driver, self, 2)
				driver:set_detach()
				driver:set_eye_offset(vector_zero(), vector_zero())
				remove_physics_overrides(driver)
				driver:add_velocity(self.object:get_velocity())
				update_hud(self.driver, driver)
				self.object:remove()
				return
			end
		end
		--luaent = nil
	end

	self.time_from_last_rocket = math_min(
		self.time_from_last_rocket + dtime, rocket_cooldown)

	local vel = self.object:get_velocity()
	local speed = self.speed
	local rot = self.object:get_rotation()
	local pos = self.object:get_pos()

	-- Check surroundings
	local land = false
	local crash_speed, crash_damage = 0
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
		crash_damage = math_floor(math_max(crash_speed - 5, 0))
		if crash_damage > 0 then
			local node = minetest.get_node(pos)
			if minetest.registered_nodes[node.name].liquidtype == "none" then
				-- damage glider first
				damage_glider(driver, self, crash_damage)
				damage_driver(driver, crash_damage)
			end
		end
	elseif not friendly_airspace(pos, self.driver, self.xp, self.privs) then
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
			-- destroy glider
			damage_glider(driver, self, 1 + 65535 / crash_damage_wear_factor)
			shoot_flak_sound(pos)
			land = true
		end
	else
		land, crash_damage = custom_grounded_checks(self.driver, driver, self)
		if 0 ~= crash_damage then
			damage_glider(driver, self, crash_damage)
			damage_driver(driver, crash_damage)
		end
	end

	if land then
		driver:set_detach()
		driver:set_eye_offset(vector_zero(), vector_zero())
		remove_physics_overrides(driver)
		driver:add_velocity(vel)
		self.object:remove()
		equip_sound(pos)
		update_hud(self.driver, driver)
		return
	end

	local mouse, pro = player_controls(driver)
	if mouse then
		local ver = driver:get_look_vertical()
		if not pro then
			rot.x = rot.x + (-ver - rot.x) * dtime * 2
		else
			rot.x = rot.x + (ver - rot.x) * dtime * 2
		end
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
		local keys = driver:get_player_control()
		-- ignore if both directions are pressed
		if keys.up or keys.down then
			if not pro then
				-- inverted controls
				if keys.up then
					rot.x = rot.x + dtime * 0.25
				elseif keys.down then
					rot.x = rot.x - dtime * 0.25
				end
			else
				-- pro pilot controls: forward pushes
				-- nose down, back pulls up
				if keys.up then
					rot.x = rot.x - dtime * 0.25
				elseif keys.down then
					rot.x = rot.x + dtime * 0.25
				end
			end
		end
		-- ignore if both directions are pressed
		if keys.left or keys.right then
			if keys.left then
				rot.z = rot.z - 2 * dtime * 0.5
			elseif keys.right then
				rot.z = rot.z + 2 * dtime * 0.5
			end
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

	speed = math_min(max_speed, math_max(2,
		(speed - (rot.x ^ 3) * 4 * dtime) - speed * 0.01 * dtime))

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
	update_hud(self.driver, driver, rot,
		rocket_cooldown - self.time_from_last_rocket, speed, dir.y)
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
			update_hud(name, driver)
		end
	else
		if not glider.allow_while_hanggliding then
			for _, obj in ipairs(driver:get_children()) do
				luaent = obj:get_luaentity()
				if luaent and luaent.name == "hangglider:glider" then
					return
				end
			end
		end

		local grounded, damage = custom_grounded_checks(name, driver)
		if grounded then
			if 0 ~= damage then
				itemstack:add_wear(damage * crash_damage_wear_factor)
				damage_driver(driver, damage)
			end
			return itemstack
		end

		pos.y = pos.y + 1.5
		local ent = minetest.add_entity(pos, "glider:hangglider")
		if not ent then
			-- failed to create entity -> abort
			return
		end

		luaent = ent:get_luaentity()
		luaent.driver = name
		if has_xp_redo then
			luaent.xp = xp_redo.get_xp(name)
		end
		if has_priv_protector then
			luaent.privs = minetest.get_player_privs(name)
		end
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

local function on_place(_, driver)
	if type(driver) ~= "userdata" then
		return  -- Real players only
	end

	local meta = driver:get_meta()
	local keys = driver:get_player_control()

	if keys.aux1 and keys.sneak then
		-- change inverted up/down
		-- read and toggle in one line
		local pro = 0 == meta:get_int("glider.pro")
		meta:set_int("glider.pro", pro and 1 or 0)

		minetest.chat_send_player(driver:get_player_name(),
			pro
				and "Normal up/down activated (pro pilot)."
				or "Inverted up/down activated (novice).")

	elseif mouse_controls and keyboard_controls
		and keys.sneak
	then
		-- toggle mouse/keyboard control
		-- read and toggle in one line
		local key_c = 0 == meta:get_int("glider.keyC")
		meta:set_int("glider.keyC", key_c and 1 or 0)

		minetest.chat_send_player(driver:get_player_name(),
			key_c
				and "Keyboard controls activated."
				or "Mouse controls activated.")
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
	time_from_last_rocket = rocket_cooldown,
})

minetest.register_tool("glider:glider", {
	description = "Delta Glider",
	inventory_image = "glider_glider.png",
	on_use = on_use,
	on_secondary_use = on_place,
})

local mp = minetest.get_modpath("glider")
dofile(mp .. "/crafts.lua")
if use_rockets then
	dofile(mp .. "/rocket.lua")
end

minetest.register_on_dieplayer(function(player)
	remove_physics_overrides(player)
	update_hud(player:get_player_name(), player)
end)

minetest.register_on_leaveplayer(function(player)
	remove_physics_overrides(player)
	huds[player:get_player_name()] = nil
end)

print("[glider] loaded with"
	.. (use_rockets and " " or "out ") .. "rockets.")

