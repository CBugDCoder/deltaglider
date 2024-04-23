
local S = deltaglider.translator

local has_basic_materials = minetest.get_modpath("basic_materials")
local has_farming = minetest.get_modpath("farming")
local has_pipeworks = minetest.get_modpath("pipeworks")
local has_ropes = minetest.get_modpath("ropes")
local has_unifieddyes = minetest.get_modpath("unifieddyes")
local has_wool = minetest.get_modpath("wool")

local dye_colors = {
	white      = "ffffff",
	grey       = "888888",
	dark_grey  = "444444",
	black      = "111111",
	violet     = "8000ff",
	blue       = "0000ff",
	cyan       = "00ffff",
	dark_green = "005900",
	green      = "00ff00",
	yellow     = "ffff00",
	brown      = "592c00",
	orange     = "ff7f00",
	red        = "ff0000",
	magenta    = "ff00ff",
	pink       = "ff7f9f",
}

local translated_colors = {
	white      = S("White"),
	grey       = S("Grey"),
	dark_grey  = S("Dark_grey"),
	black      = S("Black"),
	violet     = S("Violet"),
	blue       = S("Blue"),
	cyan       = S("Cyan"),
	dark_green = S("Dark_green"),
	green      = S("Green"),
	yellow     = S("Yellow"),
	brown      = S("Brown"),
	orange     = S("Orange"),
	red        = S("Red"),
	magenta    = S("Magenta"),
	pink       = S("Pink"),
}

local function get_dye_color(name)
	local color
	if has_unifieddyes then
		color = unifieddyes.get_color_from_dye_name(name)
	end
	if not color then
		color = string.match(name, "^dye:(.+)$")
		if color then
			color = dye_colors[color]
		end
	end
	return color
end

local function get_color_name(name)
	name = string.gsub(name, "^dye:", "")
	return translated_colors[name]
end

local function get_color_name_from_color(color)
	for name, color_hex in pairs(dye_colors) do
		if color == color_hex then
			return translated_colors[name]
		end
	end

	return nil
end

-- This recipe is just a placeholder
do
	local item = ItemStack("deltaglider:glider")
	item:get_meta():set_string("description", S("Coloured Delta Glider"))
	minetest.register_craft({
		output = item:to_string(),
		recipe = { "deltaglider:glider", "group:dye" },
		type = "shapeless",
	})
end

-- This is what actually creates the colored hangglider
minetest.register_on_craft(function(crafted_item, _, old_craft_grid)
	if crafted_item:get_name() ~= "deltaglider:glider" then
		return
	end
	local wear, color, color_name
	for _ ,stack in ipairs(old_craft_grid) do
		local name = stack:get_name()
		if name == "deltaglider:glider" then
			wear = stack:get_wear()
			color = stack:get_meta():get("glider_color")
			color_name = get_color_name_from_color(color)
		elseif minetest.get_item_group(name, "dye") ~= 0 then
			color = get_dye_color(name)
			color_name = get_color_name(name)
		elseif "wool:white" == stack:get_name()
			or "default:paper" == stack:get_name()
		then
			wear = 0
		end
	end
	if wear and color and color_name then
		if color == "ffffff" then
			return ItemStack({ name = "deltaglider:glider", wear = wear })
		end

		local meta = crafted_item:get_meta()
		meta:set_string("description", S("@1 Delta Glider", color_name))
		meta:set_string("inventory_image",
			"deltaglider_glider.png^(deltaglider_glider_color.png^[multiply:#"
			.. color .. ")")
		meta:set_string("glider_color", color)
		crafted_item:set_wear(wear)
		return crafted_item
	end
end)

-- Repairing
minetest.register_craft({
	output = "deltaglider:glider",
	recipe = {
		{ "default:paper", "default:paper", "default:paper" },
		{ "default:paper", "deltaglider:glider", "default:paper" },
		{ "default:paper", "default:paper", "default:paper" },
	},
})
if has_wool then
	minetest.register_craft({
		output = "deltaglider:glider",
		recipe = {
			{ "deltaglider:glider", "wool:white" },
		},
	})
end

-- Main craft
local fabric = "default:paper"
local stick = "group:stick"
local string = ""
if has_wool then
	fabric = "wool:white"
end
if has_farming then
	string = "farming:string"
end
if has_ropes then
	string = "ropes:ropesegment"
end
if has_basic_materials then
	fabric = "basic_materials:plastic_sheet"
	string = "basic_materials:steel_wire"
	stick = "basic_materials:steel_strip"
end
if has_pipeworks then
	stick = "pipeworks:tube_1"
end

minetest.register_craft({
	output = "deltaglider:glider",
	recipe = {
		{ string, fabric, string },
		{ fabric, fabric, fabric },
		{ stick, stick, stick },
	}
})

