local function rot_to_dir(rot)
	local x = -math.cos(rot.x) * math.sin(rot.y)
	local y = math.sin(rot.x)
	local z = math.cos(rot.x) * math.cos(rot.y)
	return {x = x, y = y, z = z}
end

local mouse_controls = minetest.settings:get_bool("glider_mouse_controls", true)

local on_step = function(self, dtime, moveresult)
	local vel = self.object:get_velocity()
	local speed = self.speed
	local actual_speed = math.sqrt(vel.x^2+vel.y^2+vel.z^2)
	local rot = self.object:get_rotation()
	local driver = minetest.get_player_by_name(self.driver)
	local pos = self.object:get_pos()
	
	--Check Surroundings
	local land = false
	local crash_speed = 0
	if moveresult and moveresult.collisions and moveresult.collides then
		for _,collision in pairs(moveresult.collisions) do
			land = true
			crash_speed = crash_speed+
						  math.abs(collision.old_velocity.x-collision.new_velocity.x)+
						  math.abs(collision.old_velocity.y-collision.new_velocity.y)+
						  math.abs(collision.old_velocity.z-collision.new_velocity.z)
		end
	end
	
	if land then
		driver:set_detach()
		driver:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
		driver:add_player_velocity(vel)
		local crash_dammage = math.floor(math.max(crash_speed-5, 0))
		if crash_dammage > 0 then
			local node = minetest.get_node(pos)
			if minetest.registered_nodes[node.name].liquidtype == "none" then
				local hp = driver:get_hp()
				driver:set_hp(hp-crash_dammage, {type = "fall"})
			end
		end
		self.object:remove()
	end
	
	if mouse_controls then
		rot.x = rot.x + (-driver:get_look_vertical()-rot.x)*(dtime*2)
		local hor = driver:get_look_horizontal()
		local angle = hor-rot.y
		if angle < -math.pi then angle = angle + math.pi*2 end
		if angle > math.pi then angle = angle - math.pi*2 end
		rot.y = rot.y + angle*(dtime*2)
		speed = speed - math.abs(angle*dtime)
		rot.z = -angle
	else
		local control = driver:get_player_control()
		if control.up then
			rot.x = rot.x + dtime
		end
		if control.down then
			rot.x = rot.x - dtime
		end
		if control.left then
			rot.z = rot.z - 2*dtime
		end
		if control.right then
			rot.z = rot.z + 2*dtime
		end
		
		if rot.z ~= 0 then
			speed = speed - math.abs(rot.z*dtime)
			if math.abs(rot.z) < 0.01 then
				rot.z = 0
			end
			rot.y = rot.y - (rot.z*dtime)
			rot.z = rot.z - rot.z*dtime
		end
	end
	
	speed = math.max(speed - (rot.x^3)*4 * dtime, 2)
	self.object:set_rotation(rot)
	local dir = rot_to_dir(rot)
	local gravity = -20 * (((speed)/4)^-1)/2
	dir = {x = dir.x*speed, y = dir.y*speed+gravity, z = dir.z*speed}
	self.speed = speed
	self.object:set_velocity(dir)
end




minetest.register_entity("glider:hangglider", {
	physical = true,
	pointable = false,
	visual = "mesh",
	mesh = "glider_hangglider.obj",
	textures = {"glider_hangglider.png"},
	static_save = false,
	--Functions
	on_step = on_step,
	driver = "",
	free_fall = false,
	speed = 0,
})

minetest.register_tool("glider:glider", {
	description = "Glider",
	inventory_image = "glider_glider.png",
	on_use = function(itemstack, user, pt)
		local name = user:get_player_name()
		local pos = user:get_pos()
		local attach = user:get_attach()
		local luaent = nil
		if attach then 
			luaent = attach:get_luaentity()
			if luaent.name == "glider:hangglider" then
				local vel = attach:get_velocity()
				attach:remove()
				user:set_detach()
				user:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
				user:add_player_velocity(vel)
			end
		else
			pos.y = pos.y + 1.5
			local ent = minetest.add_entity(pos, "glider:hangglider")
			luaent = ent:get_luaentity()
			luaent.driver = name
			local rot = {y = user:get_look_horizontal(), x = -user:get_look_vertical(), z = 0}
			ent:set_rotation(rot)
			local vel = vector.multiply(user:get_player_velocity(),2)
			ent:set_velocity(vel)
			luaent.speed = math.sqrt(vel.x^2+(vel.y/4)^2+vel.z^2)
			user:set_attach(ent, "", {x=0,y=0,z=-10}, {x=90,y=0,z=0})
			user:set_eye_offset({x=0,y=-16.25,z=0},{x=0,y=-15,z=0})
		end
	end,
})

minetest.register_craftitem("glider:rocket", {
	description = "Rocket (Use while gliding to boost glider speed)",
	inventory_image = "glider_rocket.png",
	on_use = function(itemstack, user, pt)
		local attach = user:get_attach()
		if attach then
			local luaent = attach:get_luaentity()
			if luaent.name == "glider:hangglider" then
				luaent.speed = luaent.speed + 10
				itemstack:take_item()
				minetest.add_particlespawner({
					amount = 1000,
					time = 2,
					minpos = {x = -0.125, y = -0.125, z = -0.125},
					maxpos = {x = 0.125, y = 0.125, z = 0.125},
					minexptime = 0.5,
					maxexptime = 1.5,
					attached = attach,
					texture = "glider_rocket_particle.png",
				})
				return itemstack
			end
		end
	end
})

minetest.register_craft({
	output = "glider:glider",
	recipe = {
		{"group:wool", "group:wool", "group:wool" },
		{"group:stick","",           "group:stick"},
		{"",           "group:stick",""           },
	}
})

minetest.register_craft({
	output = "glider:rocket 33",
	recipe = {
		{"group:wood","tnt:gunpowder","group:wood"},
		{"group:wood","tnt:gunpowder","group:wood"},
		{"group:wood","tnt:gunpowder","group:wood"},
	}
})
