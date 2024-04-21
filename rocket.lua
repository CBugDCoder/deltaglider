local S = deltaglider.translator
local rocket_cooldown = deltaglider.rocket_cooldown

minetest.register_craftitem("deltaglider:rocket", {
	description = S("Rocket (Use while gliding to boost delta glider speed)"),
	inventory_image = "deltaglider_rocket.png",
	on_use = function(itemstack, player)
		local attach = player:get_attach()
		if not attach then
			return itemstack
		end

		local luaent = attach:get_luaentity()
		if luaent.name ~= "deltaglider:hangglider" then
			return itemstack
		end

		-- Avoid rocket overuse.
		if rocket_cooldown > luaent.time_from_last_rocket then
			return itemstack
		end

		luaent.speed = luaent.speed + luaent.time_from_last_rocket
		luaent.time_from_last_rocket = 0

		-- Add some fancy particles
		minetest.add_particlespawner({
			amount = 200,
			time = 2,
			minpos = { x = -0.05, y = -0.05, z = -0.05 },
			maxpos = { x = 0.05, y = 0.05, z = 0.05 },
			minexptime = 1,
			maxexptime = 2,
			attached = attach,
			texture = "deltaglider_rocket_particle.png",
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
	output = "deltaglider:rocket 33",
	recipe = {
		{ "group:wood", gunpowder, "group:wood" },
		{ "group:wood", gunpowder, "group:wood" },
		{ "group:wood", gunpowder, "group:wood" },
	}
})

