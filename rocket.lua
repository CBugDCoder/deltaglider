local rocket_cooldown = glider.rocket_cooldown

minetest.register_craftitem("glider:rocket", {
	description = "Rocket (Use while gliding to boost delta glider speed)",
	inventory_image = "glider_rocket.png",
	on_use = function(itemstack, driver, pt) --luacheck: no unused args
		local attach = driver:get_attach()
		if not attach then
			return itemstack
		end

		local luaent = attach:get_luaentity()
		if luaent.name ~= "glider:hangglider" then
			return itemstack
		end

		-- Avoid rocket overuse. This also throttles max speed.
		if rocket_cooldown > luaent.time_from_last_rocket then
			return itemstack
		end

		luaent.speed = luaent.speed + luaent.time_from_last_rocket
		luaent.time_from_last_rocket = 0

		-- Add some fancy particles
		minetest.add_particlespawner({
			amount = 1000,
			time = 2,
			minpos = { x = -0.125, y = -0.125, z = -0.125 },
			maxpos = { x = 0.125, y = 0.125, z = 0.125 },
			minexptime = 0.5,
			maxexptime = 1.5,
			attached = attach,
			texture = "glider_rocket_particle.png",
		})

		-- Use a rocket
		itemstack:take_item()
		return itemstack
	end
})

local gunpowder = minetest.get_modpath("mcl_mobitems")
	and "mcl_mobitems:gunpowder"
	or "tnt:gunpowder"

minetest.register_craft({
	output = "glider:rocket 33",
	recipe = {
		{ "group:wood", gunpowder, "group:wood" },
		{ "group:wood", gunpowder, "group:wood" },
		{ "group:wood", gunpowder, "group:wood" },
	}
})

