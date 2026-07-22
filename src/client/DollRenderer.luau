--!strict
-- The paper doll: a chibi mannequin drawn entirely from UI primitives, so every
-- catalog item visibly goes ON the character — the heart of the dress-up loop.
-- Data-driven: RECIPES maps itemId → a list of shapes in doll-box fractions
-- (x/y = center, w/h = size, 0..1 of the doll frame). Real 3D avatars replace
-- this once the catalog gets real assetIds (spec §9.8); the paper-doll style
-- deliberately matches the "editorial paper" art direction until then.
--
-- Shape spec fields:
--   k = "r" rect | "e" ellipse | "t" emoji/text sticker
--   x, y, w, h        center + size, fractions of the doll box
--   c                 color: nil = item color, "D" = darkened item color,
--                     "skin" | "white" | "ink" | Color3
--   t                 BackgroundTransparency (default 0)
--   rot               rotation degrees
--   z                 layer 1..9 (1 behind body … 9 over everything)
--   corner            corner radius as fraction of shape height (default 0.5)
--   text              glyph for k = "t"
--
-- Layers: 1 back (wings/hair-back/hood) · 2-3 body · 4 shoes · 5 bottoms ·
-- 6 tops+sleeves · 7 hair front/neck · 8 face · 9 head gear.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local DollRenderer = {}

local ASPECT = 0.62 -- doll box width / height

local SKIN = Color3.fromRGB(246, 208, 178)
local SKIN_D = Color3.fromRGB(226, 182, 150)
local INK = Color3.fromRGB(48, 32, 70)
local WHITE = Color3.fromRGB(250, 248, 252)
local BLUSH = Color3.fromRGB(247, 154, 174)
local BASICS = Color3.fromRGB(214, 206, 226) -- undersuit when a slot is empty

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function darken(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount or 0.22)
end

type Shape = {
	k: string?,
	x: number,
	y: number,
	w: number,
	h: number,
	c: any?,
	t: number?,
	rot: number?,
	z: number?,
	corner: number?,
	text: string?,
}

type Recipe = { color: Color3, shapes: { Shape } }

-- ============================ the body ============================

local BODY: { Shape } = {
	-- legs, feet, torso, neck, arms, head — all skin
	{ k = "r", x = 0.445, y = 0.72, w = 0.10, h = 0.32, c = "skin", z = 2, corner = 0.16 },
	{ k = "r", x = 0.555, y = 0.72, w = 0.10, h = 0.32, c = "skin", z = 2, corner = 0.16 },
	{ k = "e", x = 0.445, y = 0.893, w = 0.115, h = 0.05, c = "skin", z = 2 },
	{ k = "e", x = 0.555, y = 0.893, w = 0.115, h = 0.05, c = "skin", z = 2 },
	{ k = "r", x = 0.5, y = 0.445, w = 0.32, h = 0.235, c = "skin", z = 2, corner = 0.3 },
	{ k = "r", x = 0.5, y = 0.305, w = 0.10, h = 0.06, c = "skin", z = 2, corner = 0.4 },
	{ k = "r", x = 0.295, y = 0.44, w = 0.075, h = 0.225, c = "skin", z = 3, rot = 10, corner = 0.5 },
	{ k = "r", x = 0.705, y = 0.44, w = 0.075, h = 0.225, c = "skin", z = 3, rot = -10, corner = 0.5 },
	{ k = "e", x = 0.5, y = 0.158, w = 0.42, h = 0.275, c = "skin", z = 2 },
}

local FACE: { Shape } = {
	{ k = "e", x = 0.425, y = 0.163, w = 0.045, h = 0.062, c = "ink", z = 8 },
	{ k = "e", x = 0.575, y = 0.163, w = 0.045, h = 0.062, c = "ink", z = 8 },
	{ k = "e", x = 0.437, y = 0.148, w = 0.016, h = 0.02, c = "white", z = 9 },
	{ k = "e", x = 0.587, y = 0.148, w = 0.016, h = 0.02, c = "white", z = 9 },
	{ k = "e", x = 0.378, y = 0.212, w = 0.055, h = 0.028, c = BLUSH, t = 0.35, z = 8 },
	{ k = "e", x = 0.622, y = 0.212, w = 0.055, h = 0.028, c = BLUSH, t = 0.35, z = 8 },
	{ k = "e", x = 0.5, y = 0.235, w = 0.05, h = 0.024, c = rgb(196, 92, 110), z = 8 },
}

-- Neutral looks for empty slots: soft bob + plain basics, never a bare doll.
local DEFAULT_HAIR: { Shape } = {
	{ k = "e", x = 0.5, y = 0.10, w = 0.48, h = 0.20, c = rgb(112, 82, 72), z = 7 },
	{ k = "r", x = 0.30, y = 0.19, w = 0.09, h = 0.17, c = rgb(112, 82, 72), z = 7, corner = 0.45 },
	{ k = "r", x = 0.70, y = 0.19, w = 0.09, h = 0.17, c = rgb(112, 82, 72), z = 7, corner = 0.45 },
}
local DEFAULT_TOP: { Shape } = {
	{ k = "r", x = 0.5, y = 0.43, w = 0.33, h = 0.17, c = BASICS, z = 6, corner = 0.25 },
	{ k = "r", x = 0.41, y = 0.345, w = 0.05, h = 0.05, c = BASICS, z = 6 },
	{ k = "r", x = 0.59, y = 0.345, w = 0.05, h = 0.05, c = BASICS, z = 6 },
}
local DEFAULT_BOTTOM: { Shape } = {
	{ k = "r", x = 0.5, y = 0.585, w = 0.345, h = 0.095, c = darken(BASICS, 0.12), z = 5, corner = 0.3 },
}

-- ============================ item recipes ============================

local RECIPES: { [string]: Recipe } = {
	-- ---------------- hair (z1 back mass, z7 front, z9 extras) ----------------
	["hair_bob"] = {
		color = rgb(109, 76, 65),
		shapes = {
			{ k = "e", x = 0.5, y = 0.095, w = 0.5, h = 0.21, z = 7 },
			{ k = "r", x = 0.295, y = 0.20, w = 0.10, h = 0.20, z = 7, corner = 0.4 },
			{ k = "r", x = 0.705, y = 0.20, w = 0.10, h = 0.20, z = 7, corner = 0.4 },
		},
	},
	["hair_space_buns"] = {
		color = rgb(87, 58, 46),
		shapes = {
			{ k = "e", x = 0.5, y = 0.10, w = 0.46, h = 0.19, z = 7 },
			{ k = "e", x = 0.315, y = 0.045, w = 0.16, h = 0.10, z = 9 },
			{ k = "e", x = 0.685, y = 0.045, w = 0.16, h = 0.10, z = 9 },
		},
	},
	["hair_long_waves"] = {
		color = rgb(176, 126, 74),
		shapes = {
			{ k = "e", x = 0.5, y = 0.22, w = 0.56, h = 0.42, z = 1 },
			{ k = "e", x = 0.5, y = 0.095, w = 0.5, h = 0.21, z = 7 },
			{ k = "r", x = 0.28, y = 0.31, w = 0.10, h = 0.34, z = 7, corner = 0.45 },
			{ k = "r", x = 0.72, y = 0.31, w = 0.10, h = 0.34, z = 7, corner = 0.45 },
		},
	},
	["hair_pixie"] = {
		color = rgb(58, 44, 66),
		shapes = {
			{ k = "e", x = 0.5, y = 0.09, w = 0.46, h = 0.185, z = 7 },
			{ k = "r", x = 0.33, y = 0.155, w = 0.075, h = 0.09, z = 7, rot = 14, corner = 0.5 },
		},
	},
	["hair_puffs"] = {
		color = rgb(66, 44, 38),
		shapes = {
			{ k = "e", x = 0.5, y = 0.10, w = 0.46, h = 0.19, z = 7 },
			{ k = "e", x = 0.30, y = 0.035, w = 0.20, h = 0.13, z = 9 },
			{ k = "e", x = 0.70, y = 0.035, w = 0.20, h = 0.13, z = 9 },
		},
	},
	["hair_pony"] = {
		color = rgb(150, 100, 60),
		shapes = {
			{ k = "e", x = 0.5, y = 0.095, w = 0.47, h = 0.195, z = 7 },
			{ k = "e", x = 0.665, y = 0.035, w = 0.13, h = 0.085, z = 9 },
			{ k = "r", x = 0.73, y = 0.16, w = 0.085, h = 0.26, z = 1, rot = -12, corner = 0.5 },
		},
	},
	["hair_braid"] = {
		color = rgb(222, 180, 120),
		shapes = {
			{ k = "e", x = 0.5, y = 0.095, w = 0.48, h = 0.20, z = 7 },
			{ k = "e", x = 0.30, y = 0.24, w = 0.085, h = 0.085, z = 7 },
			{ k = "e", x = 0.295, y = 0.315, w = 0.075, h = 0.075, z = 7 },
			{ k = "e", x = 0.29, y = 0.38, w = 0.065, h = 0.065, z = 7 },
		},
	},

	-- ---------------- tops (z6, sleeves included) ----------------
	["top_crop_tee"] = {
		color = rgb(244, 143, 177),
		shapes = {
			{ k = "r", x = 0.5, y = 0.405, w = 0.345, h = 0.135, z = 6, corner = 0.25 },
			{ k = "r", x = 0.295, y = 0.375, w = 0.085, h = 0.085, z = 6, rot = 10, corner = 0.4 },
			{ k = "r", x = 0.705, y = 0.375, w = 0.085, h = 0.085, z = 6, rot = -10, corner = 0.4 },
		},
	},
	["top_hoodie"] = {
		color = rgb(156, 146, 180),
		shapes = {
			{ k = "e", x = 0.5, y = 0.29, w = 0.34, h = 0.14, z = 1 }, -- hood behind head
			{ k = "r", x = 0.5, y = 0.45, w = 0.42, h = 0.245, z = 6, corner = 0.22 },
			{ k = "r", x = 0.29, y = 0.45, w = 0.10, h = 0.235, z = 6, rot = 10, corner = 0.5 },
			{ k = "r", x = 0.71, y = 0.45, w = 0.10, h = 0.235, z = 6, rot = -10, corner = 0.5 },
			{ k = "r", x = 0.5, y = 0.50, w = 0.18, h = 0.075, c = "D", z = 6, corner = 0.3 },
		},
	},
	["top_blouse"] = {
		color = rgb(250, 240, 225),
		shapes = {
			{ k = "r", x = 0.5, y = 0.43, w = 0.35, h = 0.185, z = 6, corner = 0.25 },
			{ k = "e", x = 0.30, y = 0.36, w = 0.11, h = 0.10, z = 6 },
			{ k = "e", x = 0.70, y = 0.36, w = 0.11, h = 0.10, z = 6 },
			{ k = "e", x = 0.40, y = 0.525, w = 0.075, h = 0.05, z = 6 },
			{ k = "e", x = 0.50, y = 0.535, w = 0.075, h = 0.05, z = 6 },
			{ k = "e", x = 0.60, y = 0.525, w = 0.075, h = 0.05, z = 6 },
		},
	},
	["top_corset"] = {
		color = rgb(233, 155, 180),
		shapes = {
			{ k = "r", x = 0.5, y = 0.44, w = 0.30, h = 0.20, z = 6, corner = 0.2 },
			{ k = "r", x = 0.5, y = 0.395, w = 0.22, h = 0.012, c = "D", z = 7 },
			{ k = "r", x = 0.5, y = 0.44, w = 0.22, h = 0.012, c = "D", z = 7 },
			{ k = "r", x = 0.5, y = 0.485, w = 0.22, h = 0.012, c = "D", z = 7 },
		},
	},
	["top_jersey"] = {
		color = rgb(0, 137, 123),
		shapes = {
			{ k = "r", x = 0.5, y = 0.44, w = 0.38, h = 0.215, z = 6, corner = 0.22 },
			{ k = "r", x = 0.29, y = 0.385, w = 0.09, h = 0.10, z = 6, rot = 10, corner = 0.4 },
			{ k = "r", x = 0.71, y = 0.385, w = 0.09, h = 0.10, z = 6, rot = -10, corner = 0.4 },
			{ k = "r", x = 0.5, y = 0.44, w = 0.075, h = 0.215, c = "white", t = 0.25, z = 6 },
		},
	},
	["top_puffer"] = {
		color = rgb(150, 200, 235),
		shapes = {
			{ k = "r", x = 0.5, y = 0.445, w = 0.43, h = 0.24, z = 6, corner = 0.25 },
			{ k = "r", x = 0.285, y = 0.445, w = 0.105, h = 0.23, z = 6, rot = 10, corner = 0.5 },
			{ k = "r", x = 0.715, y = 0.445, w = 0.105, h = 0.23, z = 6, rot = -10, corner = 0.5 },
			{ k = "r", x = 0.5, y = 0.40, w = 0.40, h = 0.012, c = "D", z = 7 },
			{ k = "r", x = 0.5, y = 0.465, w = 0.40, h = 0.012, c = "D", z = 7 },
			{ k = "r", x = 0.5, y = 0.53, w = 0.40, h = 0.012, c = "D", z = 7 },
		},
	},
	["top_mesh"] = {
		color = rgb(70, 52, 100),
		shapes = {
			{ k = "r", x = 0.5, y = 0.435, w = 0.35, h = 0.19, t = 0.45, z = 6, corner = 0.25 },
			{ k = "r", x = 0.295, y = 0.44, w = 0.07, h = 0.21, t = 0.45, z = 6, rot = 10, corner = 0.5 },
			{ k = "r", x = 0.705, y = 0.44, w = 0.07, h = 0.21, t = 0.45, z = 6, rot = -10, corner = 0.5 },
		},
	},

	-- ---------------- bottoms (z5) ----------------
	["bot_cargo"] = {
		color = rgb(150, 140, 110),
		shapes = {
			{ k = "r", x = 0.5, y = 0.575, w = 0.36, h = 0.08, z = 5, corner = 0.3 },
			{ k = "r", x = 0.44, y = 0.72, w = 0.135, h = 0.30, z = 5, corner = 0.2 },
			{ k = "r", x = 0.56, y = 0.72, w = 0.135, h = 0.30, z = 5, corner = 0.2 },
			{ k = "r", x = 0.44, y = 0.68, w = 0.09, h = 0.05, c = "D", z = 6, corner = 0.25 },
			{ k = "r", x = 0.56, y = 0.68, w = 0.09, h = 0.05, c = "D", z = 6, corner = 0.25 },
		},
	},
	["bot_pleated"] = {
		color = rgb(64, 72, 118),
		shapes = {
			{ k = "r", x = 0.5, y = 0.615, w = 0.42, h = 0.13, z = 5, corner = 0.25 },
			{ k = "r", x = 0.41, y = 0.615, w = 0.012, h = 0.12, c = "D", z = 6 },
			{ k = "r", x = 0.47, y = 0.615, w = 0.012, h = 0.12, c = "D", z = 6 },
			{ k = "r", x = 0.53, y = 0.615, w = 0.012, h = 0.12, c = "D", z = 6 },
			{ k = "r", x = 0.59, y = 0.615, w = 0.012, h = 0.12, c = "D", z = 6 },
		},
	},
	["bot_flare"] = {
		color = rgb(78, 106, 168),
		shapes = {
			{ k = "r", x = 0.5, y = 0.575, w = 0.35, h = 0.075, z = 5, corner = 0.3 },
			{ k = "r", x = 0.445, y = 0.70, w = 0.105, h = 0.19, z = 5, corner = 0.2 },
			{ k = "r", x = 0.555, y = 0.70, w = 0.105, h = 0.19, z = 5, corner = 0.2 },
			{ k = "r", x = 0.43, y = 0.845, w = 0.15, h = 0.13, z = 5, rot = 6, corner = 0.2 },
			{ k = "r", x = 0.57, y = 0.845, w = 0.15, h = 0.13, z = 5, rot = -6, corner = 0.2 },
		},
	},
	["bot_tutu"] = {
		color = rgb(210, 190, 255),
		shapes = {
			{ k = "e", x = 0.5, y = 0.60, w = 0.54, h = 0.115, t = 0.25, z = 5 },
			{ k = "e", x = 0.5, y = 0.635, w = 0.48, h = 0.105, t = 0.35, z = 5 },
			{ k = "e", x = 0.5, y = 0.665, w = 0.42, h = 0.095, t = 0.45, z = 5 },
		},
	},
	["bot_leggings"] = {
		color = rgb(64, 60, 76),
		shapes = {
			{ k = "r", x = 0.5, y = 0.575, w = 0.35, h = 0.07, z = 5, corner = 0.3 },
			{ k = "r", x = 0.445, y = 0.72, w = 0.10, h = 0.31, z = 5, corner = 0.16 },
			{ k = "r", x = 0.555, y = 0.72, w = 0.10, h = 0.31, z = 5, corner = 0.16 },
		},
	},
	["bot_denim_mini"] = {
		color = rgb(122, 152, 202),
		shapes = {
			{ k = "r", x = 0.5, y = 0.60, w = 0.37, h = 0.10, z = 5, corner = 0.25 },
			{ k = "r", x = 0.5, y = 0.565, w = 0.37, h = 0.018, c = "D", z = 6 },
		},
	},
	["bot_parachute"] = {
		color = rgb(172, 176, 188),
		shapes = {
			{ k = "r", x = 0.5, y = 0.575, w = 0.37, h = 0.075, z = 5, corner = 0.3 },
			{ k = "r", x = 0.43, y = 0.715, w = 0.175, h = 0.26, z = 5, corner = 0.35 },
			{ k = "r", x = 0.57, y = 0.715, w = 0.175, h = 0.26, z = 5, corner = 0.35 },
			{ k = "r", x = 0.44, y = 0.855, w = 0.09, h = 0.045, c = "D", z = 5, corner = 0.5 },
			{ k = "r", x = 0.56, y = 0.855, w = 0.09, h = 0.045, c = "D", z = 5, corner = 0.5 },
		},
	},

	-- ---------------- shoes (z4) ----------------
	["shoe_sneaker"] = {
		color = rgb(240, 240, 245),
		shapes = {
			{ k = "r", x = 0.44, y = 0.885, w = 0.14, h = 0.06, z = 4, corner = 0.45 },
			{ k = "r", x = 0.56, y = 0.885, w = 0.14, h = 0.06, z = 4, corner = 0.45 },
			{ k = "r", x = 0.44, y = 0.912, w = 0.14, h = 0.02, c = "D", z = 5 },
			{ k = "r", x = 0.56, y = 0.912, w = 0.14, h = 0.02, c = "D", z = 5 },
		},
	},
	["shoe_ballet"] = {
		color = rgb(240, 190, 200),
		shapes = {
			{ k = "e", x = 0.445, y = 0.895, w = 0.12, h = 0.045, z = 4 },
			{ k = "e", x = 0.555, y = 0.895, w = 0.12, h = 0.045, z = 4 },
			{ k = "e", x = 0.445, y = 0.878, w = 0.035, h = 0.02, c = "D", z = 5 },
			{ k = "e", x = 0.555, y = 0.878, w = 0.035, h = 0.02, c = "D", z = 5 },
		},
	},
	["shoe_boots"] = {
		color = rgb(46, 40, 56),
		shapes = {
			{ k = "r", x = 0.44, y = 0.845, w = 0.125, h = 0.135, z = 4, corner = 0.2 },
			{ k = "r", x = 0.56, y = 0.845, w = 0.125, h = 0.135, z = 4, corner = 0.2 },
			{ k = "r", x = 0.44, y = 0.905, w = 0.135, h = 0.025, c = "D", z = 5 },
			{ k = "r", x = 0.56, y = 0.905, w = 0.135, h = 0.025, c = "D", z = 5 },
		},
	},
	["shoe_cleats"] = {
		color = rgb(228, 240, 230),
		shapes = {
			{ k = "r", x = 0.44, y = 0.89, w = 0.135, h = 0.05, z = 4, corner = 0.4 },
			{ k = "r", x = 0.56, y = 0.89, w = 0.135, h = 0.05, z = 4, corner = 0.4 },
			{ k = "r", x = 0.44, y = 0.913, w = 0.135, h = 0.016, c = "ink", z = 5 },
			{ k = "r", x = 0.56, y = 0.913, w = 0.135, h = 0.016, c = "ink", z = 5 },
		},
	},
	["shoe_maryjane"] = {
		color = rgb(122, 56, 66),
		shapes = {
			{ k = "e", x = 0.445, y = 0.893, w = 0.125, h = 0.048, z = 4 },
			{ k = "e", x = 0.555, y = 0.893, w = 0.125, h = 0.048, z = 4 },
			{ k = "r", x = 0.445, y = 0.868, w = 0.11, h = 0.014, c = "D", z = 5 },
			{ k = "r", x = 0.555, y = 0.868, w = 0.11, h = 0.014, c = "D", z = 5 },
		},
	},
	["shoe_heels"] = {
		color = rgb(206, 62, 94),
		shapes = {
			{ k = "r", x = 0.44, y = 0.88, w = 0.115, h = 0.04, z = 4, rot = -6, corner = 0.4 },
			{ k = "r", x = 0.56, y = 0.88, w = 0.115, h = 0.04, z = 4, rot = 6, corner = 0.4 },
			{ k = "r", x = 0.475, y = 0.915, w = 0.02, h = 0.045, z = 4 },
			{ k = "r", x = 0.595, y = 0.915, w = 0.02, h = 0.045, z = 4 },
		},
	},

	-- ---------------- accessories ----------------
	["acc_wings"] = {
		color = rgb(206, 232, 255),
		shapes = {
			{ k = "e", x = 0.26, y = 0.40, w = 0.24, h = 0.20, t = 0.30, z = 1, rot = 16 },
			{ k = "e", x = 0.74, y = 0.40, w = 0.24, h = 0.20, t = 0.30, z = 1, rot = -16 },
			{ k = "e", x = 0.28, y = 0.50, w = 0.15, h = 0.13, t = 0.40, z = 1, rot = 24 },
			{ k = "e", x = 0.72, y = 0.50, w = 0.15, h = 0.13, t = 0.40, z = 1, rot = -24 },
		},
	},
	["acc_chain"] = {
		color = rgb(210, 214, 226),
		shapes = {
			{ k = "e", x = 0.41, y = 0.345, w = 0.03, h = 0.03, z = 7 },
			{ k = "e", x = 0.455, y = 0.365, w = 0.03, h = 0.03, z = 7 },
			{ k = "e", x = 0.5, y = 0.372, w = 0.03, h = 0.03, z = 7 },
			{ k = "e", x = 0.545, y = 0.365, w = 0.03, h = 0.03, z = 7 },
			{ k = "e", x = 0.59, y = 0.345, w = 0.03, h = 0.03, z = 7 },
		},
	},
	["acc_bow"] = {
		color = rgb(255, 130, 170),
		shapes = {
			{ k = "e", x = 0.33, y = 0.04, w = 0.09, h = 0.07, z = 9, rot = -18 },
			{ k = "e", x = 0.42, y = 0.03, w = 0.09, h = 0.07, z = 9, rot = 18 },
			{ k = "e", x = 0.375, y = 0.045, w = 0.035, h = 0.035, c = "D", z = 9 },
		},
	},
	["acc_shades"] = {
		color = rgb(52, 44, 66),
		shapes = {
			{ k = "r", x = 0.5, y = 0.155, w = 0.36, h = 0.055, z = 9, corner = 0.45 },
			{ k = "r", x = 0.5, y = 0.145, w = 0.44, h = 0.014, z = 9 },
		},
	},
	["acc_scarf"] = {
		color = rgb(238, 176, 90),
		shapes = {
			{ k = "r", x = 0.5, y = 0.325, w = 0.20, h = 0.055, z = 7, corner = 0.5 },
			{ k = "r", x = 0.43, y = 0.42, w = 0.075, h = 0.15, z = 7, rot = 6, corner = 0.35 },
		},
	},
	["acc_cap"] = {
		color = rgb(92, 122, 220),
		shapes = {
			{ k = "e", x = 0.5, y = 0.055, w = 0.40, h = 0.13, z = 9 },
			{ k = "r", x = 0.63, y = 0.095, w = 0.20, h = 0.035, z = 9, corner = 0.5 },
		},
	},
	["acc_butterfly"] = {
		color = rgb(180, 150, 255),
		shapes = {
			{ k = "t", x = 0.33, y = 0.06, w = 0.10, h = 0.06, text = "🦋", z = 9 },
			{ k = "t", x = 0.67, y = 0.09, w = 0.08, h = 0.05, text = "🦋", z = 9 },
		},
	},
	["acc_pearls"] = {
		color = rgb(248, 244, 238),
		shapes = {
			{ k = "e", x = 0.43, y = 0.345, w = 0.028, h = 0.028, z = 7 },
			{ k = "e", x = 0.465, y = 0.36, w = 0.028, h = 0.028, z = 7 },
			{ k = "e", x = 0.5, y = 0.366, w = 0.028, h = 0.028, z = 7 },
			{ k = "e", x = 0.535, y = 0.36, w = 0.028, h = 0.028, z = 7 },
			{ k = "e", x = 0.57, y = 0.345, w = 0.028, h = 0.028, z = 7 },
		},
	},
	["acc_choker"] = {
		color = rgb(60, 46, 76),
		shapes = {
			{ k = "r", x = 0.5, y = 0.315, w = 0.13, h = 0.025, z = 7, corner = 0.5 },
			{ k = "e", x = 0.5, y = 0.328, w = 0.022, h = 0.022, c = "D", z = 8 },
		},
	},
	["acc_headphones"] = {
		color = rgb(255, 94, 180),
		shapes = {
			{ k = "r", x = 0.5, y = 0.045, w = 0.34, h = 0.035, z = 9, corner = 0.5 },
			{ k = "e", x = 0.30, y = 0.14, w = 0.085, h = 0.10, z = 9 },
			{ k = "e", x = 0.70, y = 0.14, w = 0.085, h = 0.10, z = 9 },
		},
	},
	["acc_halo"] = {
		color = rgb(255, 209, 102),
		shapes = {
			{ k = "e", x = 0.5, y = -0.015, w = 0.26, h = 0.055, t = 1, z = 9 }, -- ring via stroke
		},
	},

	-- ---------------- face (z8-9 stickers) ----------------
	["face_freckles"] = {
		color = rgb(196, 144, 108),
		shapes = {
			{ k = "e", x = 0.40, y = 0.195, w = 0.016, h = 0.016, z = 9 },
			{ k = "e", x = 0.44, y = 0.205, w = 0.016, h = 0.016, z = 9 },
			{ k = "e", x = 0.56, y = 0.205, w = 0.016, h = 0.016, z = 9 },
			{ k = "e", x = 0.60, y = 0.195, w = 0.016, h = 0.016, z = 9 },
		},
	},
	["face_glitter"] = {
		color = rgb(255, 240, 255),
		shapes = {
			{ k = "t", x = 0.37, y = 0.20, w = 0.07, h = 0.045, text = "✨", z = 9 },
			{ k = "t", x = 0.63, y = 0.20, w = 0.07, h = 0.045, text = "✨", z = 9 },
		},
	},
	["face_hearts"] = {
		color = rgb(255, 120, 160),
		shapes = {
			{ k = "t", x = 0.375, y = 0.205, w = 0.06, h = 0.04, text = "💗", z = 9 },
			{ k = "t", x = 0.625, y = 0.205, w = 0.06, h = 0.04, text = "💗", z = 9 },
		},
	},
	["face_stars"] = {
		color = rgb(255, 220, 120),
		shapes = {
			{ k = "t", x = 0.38, y = 0.20, w = 0.055, h = 0.04, text = "⭐", z = 9 },
			{ k = "t", x = 0.62, y = 0.20, w = 0.055, h = 0.04, text = "⭐", z = 9 },
			{ k = "t", x = 0.5, y = 0.105, w = 0.05, h = 0.035, text = "⭐", z = 9 },
		},
	},
}

-- ============================ drawing ============================

local function resolveColor(key: any, itemColor: Color3): Color3
	if typeof(key) == "Color3" then
		return key
	elseif key == "D" then
		return darken(itemColor)
	elseif key == "skin" then
		return SKIN
	elseif key == "white" then
		return WHITE
	elseif key == "ink" then
		return INK
	end
	return itemColor
end

local function drawShape(holder: Frame, spec: Shape, itemColor: Color3)
	if spec.k == "t" then
		local sticker = Instance.new("TextLabel")
		sticker.Text = spec.text or "✦"
		sticker.BackgroundTransparency = 1
		sticker.TextScaled = true
		sticker.AnchorPoint = Vector2.new(0.5, 0.5)
		sticker.Position = UDim2.fromScale(spec.x, spec.y)
		sticker.Size = UDim2.fromScale(spec.w, spec.h)
		sticker.Rotation = spec.rot or 0
		sticker.ZIndex = spec.z or 5
		sticker.Parent = holder
		return
	end
	local shape = Instance.new("Frame")
	shape.AnchorPoint = Vector2.new(0.5, 0.5)
	shape.Position = UDim2.fromScale(spec.x, spec.y)
	shape.Size = UDim2.fromScale(spec.w, spec.h)
	shape.BackgroundColor3 = resolveColor(spec.c, itemColor)
	shape.BackgroundTransparency = spec.t or 0
	shape.BorderSizePixel = 0
	shape.Rotation = spec.rot or 0
	shape.ZIndex = spec.z or 5
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if spec.k == "e" then UDim.new(1, 0) else UDim.new(spec.corner or 0.5, 0)
	corner.Parent = shape
	if spec.t == 1 then
		-- fully transparent fill = ring shape: show the outline instead
		local stroke = Instance.new("UIStroke")
		stroke.Color = resolveColor(spec.c, itemColor)
		stroke.Thickness = 3
		stroke.Parent = shape
	end
	shape.Parent = holder
end

local function drawList(holder: Frame, shapes: { Shape }, itemColor: Color3)
	for _, spec in shapes do
		drawShape(holder, spec, itemColor)
	end
end

-- ============================ public API ============================

export type OutfitPiece = { itemId: string, colorBucket: number? }
export type DollOutfit = { [string]: OutfitPiece? }

-- Server summary entries → the outfit map dolls draw from.
function DollRenderer.fromSummary(summary: any): DollOutfit
	local outfit: DollOutfit = {}
	if type(summary) == "table" then
		for _, entry in summary do
			if type(entry) == "table" and type(entry.itemId) == "string" and type(entry.slot) == "string" then
				outfit[entry.slot] = { itemId = entry.itemId, colorBucket = tonumber(entry.colorBucket) }
			end
		end
	end
	return outfit
end

export type Doll = {
	frame: Frame,
	setOutfit: (outfit: DollOutfit?) -> (),
	bounce: () -> (),
	celebrate: () -> (),
	setSway: (on: boolean) -> (),
	setWalk: (on: boolean) -> (),
	destroy: () -> (),
}

function DollRenderer.create(parent: Instance, props: { [string]: any }?): Doll
	local frame = Instance.new("Frame")
	frame.Name = "Doll"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	for key, value in (props or {}) :: { [string]: any } do
		(frame :: any)[key] = value
	end
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = ASPECT
	ratio.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	frame.Parent = parent

	local holder = Instance.new("Frame")
	holder.Name = "Shapes"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = frame

	local animToken = 0

	local doll = {} :: Doll
	doll.frame = frame

	function doll.setOutfit(outfit: DollOutfit?)
		holder:ClearAllChildren()
		local o = outfit or {}
		drawList(holder, BODY, SKIN)
		drawList(holder, FACE, SKIN)
		if not o.Hair then
			drawList(holder, DEFAULT_HAIR, SKIN)
		end
		if not o.Top then
			drawList(holder, DEFAULT_TOP, BASICS)
		end
		if not o.Bottom then
			drawList(holder, DEFAULT_BOTTOM, BASICS)
		end
		for _, piece in o do
			local recipe = piece and RECIPES[piece.itemId]
			if recipe and piece then
				local color = (piece.colorBucket and Config.Palette[piece.colorBucket]) or recipe.color
				drawList(holder, recipe.shapes, color)
			end
		end
	end

	function doll.bounce()
		scale.Scale = 0.9
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end

	function doll.celebrate()
		animToken += 1
		local token = animToken
		task.spawn(function()
			for _ = 1, 3 do
				if token ~= animToken or not frame.Parent then
					return
				end
				local up = TweenService:Create(
					holder,
					TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = UDim2.fromScale(0, -0.05) }
				)
				up:Play()
				up.Completed:Wait()
				local down = TweenService:Create(
					holder,
					TweenInfo.new(0.16, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
					{ Position = UDim2.fromScale(0, 0) }
				)
				down:Play()
				down.Completed:Wait()
			end
		end)
	end

	local function loopMotion(rotAmp: number, bobAmp: number, period: number)
		animToken += 1
		local token = animToken
		task.spawn(function()
			local info = TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local flip = 1
			while token == animToken and frame.Parent do
				local tween = TweenService:Create(holder, info, {
					Rotation = rotAmp * flip,
					Position = UDim2.fromScale(0, -bobAmp * (flip == 1 and 1 or 0.3)),
				})
				tween:Play()
				tween.Completed:Wait()
				flip = -flip
			end
		end)
	end

	function doll.setSway(on: boolean)
		if on then
			loopMotion(1.6, 0.004, 1.4)
		else
			animToken += 1
			holder.Rotation = 0
			holder.Position = UDim2.fromScale(0, 0)
		end
	end

	function doll.setWalk(on: boolean)
		if on then
			loopMotion(2.5, 0.014, 0.38)
		else
			animToken += 1
			holder.Rotation = 0
			holder.Position = UDim2.fromScale(0, 0)
		end
	end

	function doll.destroy()
		animToken += 1
		frame:Destroy()
	end

	doll.setOutfit(nil)
	return doll
end

return DollRenderer
