--!strict
-- Juice library: every panel borrows motion from here so the whole game shares
-- one personality — springy pops, floating hearts, confetti, crash shakes.
-- TweenService only; every effect cleans up after itself.

local TweenService = game:GetService("TweenService")

local UIFX = {}

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 79, 163),
	Color3.fromRGB(139, 92, 246),
	Color3.fromRGB(94, 234, 195),
	Color3.fromRGB(255, 209, 102),
	Color3.fromRGB(255, 250, 255),
}

-- Springy scale-in. Attaches (or reuses) a UIScale on the instance.
function UIFX.pop(inst: Instance, fromScale: number?)
	local scale = inst:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Scale = fromScale or 0.6
	scale.Parent = inst
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

-- Quick heartbeat pulse (button feedback, timers running out).
function UIFX.pulse(inst: Instance, strength: number?)
	local scale = inst:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = inst
	scale.Scale = 1 + (strength or 0.12)
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

-- Position shake for drama (crash overlay, rejected actions).
function UIFX.shake(inst: GuiObject, intensity: number?, duration: number?)
	local amp = intensity or 6
	local dur = duration or 0.45
	local origin = inst.Position
	task.spawn(function()
		local elapsed = 0
		while elapsed < dur do
			local decay = 1 - elapsed / dur
			inst.Position = origin
				+ UDim2.fromOffset(math.random(-amp, amp) * decay, math.random(-amp, amp) * decay)
			elapsed += task.wait(0.03)
		end
		inst.Position = origin
	end)
end

-- Full-parent color flash that fades out (crash hit, purchase).
function UIFX.flash(parent: Instance, color: Color3, duration: number?)
	local overlay = Instance.new("Frame")
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = 0.25
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 50
	overlay.Parent = parent
	local tween = TweenService:Create(overlay, TweenInfo.new(duration or 0.5), { BackgroundTransparency = 1 })
	tween.Completed:Connect(function()
		overlay:Destroy()
	end)
	tween:Play()
end

-- Confetti rain (podiums, rank-ups). Self-destructs when the last piece lands.
function UIFX.confetti(parent: Instance, count: number?)
	local n = count or 36
	for i = 1, n do
		task.delay(math.random() * 0.6, function()
			local piece = Instance.new("Frame")
			local size = math.random(6, 12)
			piece.Size = UDim2.fromOffset(size, math.floor(size * 0.6))
			piece.BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)]
			piece.BorderSizePixel = 0
			piece.Position = UDim2.new(math.random(), 0, -0.08, 0)
			piece.Rotation = math.random(0, 180)
			piece.ZIndex = 40
			piece.Parent = parent
			local fall = TweenService:Create(
				piece,
				TweenInfo.new(1.4 + math.random() * 1.2, Enum.EasingStyle.Linear),
				{
					Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.08, 0),
					Rotation = piece.Rotation + math.random(120, 420),
				}
			)
			fall.Completed:Connect(function()
				piece:Destroy()
			end)
			fall:Play()
		end)
	end
end

-- Little "✦" twinkles inside a frame (highlights, selected cards).
function UIFX.sparkle(parent: Instance, count: number?)
	for _ = 1, count or 6 do
		task.delay(math.random() * 0.5, function()
			local star = Instance.new("TextLabel")
			star.Text = "✦"
			star.BackgroundTransparency = 1
			star.TextColor3 = Color3.fromRGB(255, 250, 255)
			star.TextTransparency = 1
			star.Font = Enum.Font.FredokaOne
			star.TextSize = math.random(12, 22)
			star.Size = UDim2.fromOffset(24, 24)
			star.Position = UDim2.new(math.random(), -12, math.random(), -12)
			star.ZIndex = 30
			star.Parent = parent
			local inTween = TweenService:Create(star, TweenInfo.new(0.2), { TextTransparency = 0 })
			inTween.Completed:Connect(function()
				local outTween = TweenService:Create(star, TweenInfo.new(0.45), { TextTransparency = 1 })
				outTween.Completed:Connect(function()
					star:Destroy()
				end)
				outTween:Play()
			end)
			inTween:Play()
		end)
	end
end

-- Emote/text drifting upward and fading (runway reactions). x01 = 0..1 lane.
function UIFX.floatUp(parent: Instance, text: string, x01: number?)
	local lbl = Instance.new("TextLabel")
	lbl.Text = text
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextSize = math.random(24, 34)
	lbl.TextColor3 = Color3.fromRGB(255, 250, 255)
	lbl.Size = UDim2.fromOffset(44, 44)
	local x = x01 or (0.15 + math.random() * 0.7)
	lbl.Position = UDim2.new(x, -22, 0.95, 0)
	lbl.Rotation = math.random(-14, 14)
	lbl.ZIndex = 35
	lbl.Parent = parent
	local drift = TweenService:Create(
		lbl,
		TweenInfo.new(1.3 + math.random() * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.new(x + (math.random() - 0.5) * 0.12, -22, 0.55 - math.random() * 0.15, 0),
			TextTransparency = 1,
			Rotation = lbl.Rotation + math.random(-20, 20),
		}
	)
	drift.Completed:Connect(function()
		lbl:Destroy()
	end)
	drift:Play()
end

-- Animated number: label.Text runs from → to over dur. format receives the
-- current integer value and returns the display string.
function UIFX.countUp(label: TextLabel, from: number, to: number, duration: number?, format: ((n: number) -> string)?)
	local fmt = format or function(n: number)
		return tostring(n)
	end
	task.spawn(function()
		local dur = duration or 0.8
		local elapsed = 0
		while elapsed < dur do
			local alpha = 1 - (1 - elapsed / dur) ^ 3 -- ease-out cubic
			label.Text = fmt(math.floor(from + (to - from) * alpha + 0.5))
			elapsed += task.wait(0.03)
		end
		label.Text = fmt(to)
	end)
end

-- Slide a GuiObject in from a direction ("left"/"right"/"top"/"bottom").
function UIFX.slideIn(inst: GuiObject, fromDirection: string, duration: number?)
	local target = inst.Position
	local offset = {
		left = UDim2.fromScale(-0.4, 0),
		right = UDim2.fromScale(0.4, 0),
		top = UDim2.fromScale(0, -0.4),
		bottom = UDim2.fromScale(0, 0.4),
	}
	inst.Position = target + (offset[fromDirection] or offset.bottom)
	TweenService
		:Create(inst, TweenInfo.new(duration or 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = target,
		})
		:Play()
end

return UIFX
