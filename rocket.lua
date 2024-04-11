
minetest.register_craftitem("glider:rocket", {
	description = "Rocket (Use while gliding to boost delta glider speed)",
	inventory_image = "glider_rocket.png",
	on_use = function(itemstack, user, pt) --luacheck: no unused args
		local attach = user:get_attach()
		if attach then
			local luaent = attach:get_luaentity()
			if luaent.name == "glider:hangglider" then
				luaent.speed = luaent.speed + luaent.time_from_last_rocket
				luaent.time_from_last_rocket = 0
				itemstack:take_item()
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
				return itemstack
			end
		end
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

