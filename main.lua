-- VD_Main: logger animasi, remote, input, attribute + toggle + autosave
-- By: @texx-breaker

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

local FILE = "VD_Log_Live.txt"
local MAX_LOGS = 6000
local logs, running, t0, saved = {}, true, os.clock(), 0
local closed = false

local function log(kind, text)
	if not running or #logs >= MAX_LOGS then return end
	logs[#logs + 1] = string.format("[%.2f][%s] %s", os.clock() - t0, kind, text)
end

local function flush()
	if not (appendfile and writefile and isfile) then return end
	pcall(function()
		if not isfile(FILE) then writefile(FILE, "") end
		if #logs > saved then
			appendfile(FILE, table.concat(logs, "\n", saved + 1, #logs) .. "\n")
			saved = #logs
		end
	end)
end

local function ser(v, d)
	d = d or 0
	local t = typeof(v)
	if t == "string" then return '"' .. v .. '"' end
	if t == "Instance" then
		local ok, n = pcall(function() return v:GetFullName() end)
		return ok and n or tostring(v)
	end
	if t == "table" then
		if d >= 2 then return "{...}" end
		local out, n = {}, 0
		for k, x in pairs(v) do
			n += 1
			if n > 12 then out[#out + 1] = "..." break end
			out[#out + 1] = tostring(k) .. "=" .. ser(x, d + 1)
		end
		return "{" .. table.concat(out, ", ") .. "}"
	end
	return tostring(v)
end

local function dist(char)
	local a = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	local b = char and char:FindFirstChild("HumanoidRootPart")
	if a and b then return string.format("%.1f", (a.Position - b.Position).Magnitude) end
	return "?"
end

local function teamOf(plr)
	return plr.Team and plr.Team.Name or "none"
end

log("SESSION", "PlaceId=" .. game.PlaceId .. " JobId=" .. game.JobId .. " time=" .. os.time())

-- ANIMASI semua pemain
local hooked = {}
local function hookAnimator(plr, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	local function attach(animator)
		if hooked[animator] then return end
		hooked[animator] = true
		animator.AnimationPlayed:Connect(function(track)
			local anim = track.Animation
			log("ANIM", string.format(
				"%s (%s) id=%s name=%s len=%.2f prio=%s loop=%s speed=%.2f dist=%s",
				plr.Name, teamOf(plr), anim and anim.AnimationId or "?", track.Name,
				track.Length, tostring(track.Priority), tostring(track.Looped), track.Speed, dist(char)
			))
			pcall(function()
				track.KeyframeReached:Connect(function(k)
					log("KEYFRAME", plr.Name .. " " .. track.Name .. " -> " .. k)
				end)
				track.Stopped:Connect(function()
					log("ANIMSTOP", plr.Name .. " " .. track.Name)
				end)
			end)
		end)
	end
	local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5)
	if animator then attach(animator) end
	hum.ChildAdded:Connect(function(c)
		if c:IsA("Animator") then attach(c) end
	end)
end

local function hookPlayer(plr)
	if plr.Character then task.spawn(hookAnimator, plr, plr.Character) end
	plr.CharacterAdded:Connect(function(c) task.spawn(hookAnimator, plr, c) end)
end
for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
Players.PlayerAdded:Connect(hookPlayer)

-- ATTRIBUTE, child, state karakter sendiri
local function watchSelf(char)
	log("SPAWN", "karakter baru")
	for k, v in pairs(char:GetAttributes()) do log("ATTR", k .. "=" .. ser(v)) end
	char.AttributeChanged:Connect(function(k)
		log("ATTR", k .. "=" .. ser(char:GetAttribute(k)))
	end)
	char.ChildAdded:Connect(function(c) log("CHILD+", c.ClassName .. " " .. c.Name) end)
	char.ChildRemoved:Connect(function(c) log("CHILD-", c.ClassName .. " " .. c.Name) end)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.StateChanged:Connect(function(_, new) log("STATE", tostring(new)) end)
		hum.HealthChanged:Connect(function(h) log("HP", tostring(math.floor(h))) end)
	end
end
if lp.Character then task.spawn(watchSelf, lp.Character) end
lp.CharacterAdded:Connect(watchSelf)
lp.AttributeChanged:Connect(function(k) log("PLRATTR", k .. "=" .. ser(lp:GetAttribute(k))) end)

-- POSISI dan velocity saat bergerak
task.spawn(function()
	while true do
		task.wait(0.25)
		local r = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		if running and r and r.AssemblyLinearVelocity.Magnitude > 1 then
			local p, v = r.Position, r.AssemblyLinearVelocity
			log("MOVE", string.format("pos=(%.0f,%.0f,%.0f) vel=%.1f", p.X, p.Y, p.Z, v.Magnitude))
		end
	end
end)

-- INPUT
UIS.InputBegan:Connect(function(i, gpe)
	if i.UserInputType == Enum.UserInputType.Keyboard then
		log("INPUT", i.KeyCode.Name .. (gpe and " (gui)" or ""))
	elseif i.UserInputType == Enum.UserInputType.MouseButton1
		or i.UserInputType == Enum.UserInputType.MouseButton2
		or i.UserInputType == Enum.UserInputType.Touch then
		log("INPUT", i.UserInputType.Name)
	end
end)

-- REMOTE: GAME = dari game, EXEC = dari script pihak lain
local remoteHook = "tidak aktif"
if hookmetamethod and getnamecallmethod then
	local old
	old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local m = getnamecallmethod()
		if running and (m == "FireServer" or m == "InvokeServer") then
			local src = (checkcaller and checkcaller()) and "EXEC" or "GAME"
			local args = table.pack(...)
			task.spawn(function()
				local parts = {}
				for i = 1, args.n do parts[i] = ser(args[i]) end
				log("REMOTE-" .. src, m .. " " .. ser(self) .. " (" .. table.concat(parts, ", ") .. ")")
			end)
		end
		return old(self, ...)
	end))
	remoteHook = "aktif"
end

-- SNAPSHOT struktur
task.spawn(function()
	log("INFO", "remoteHook=" .. remoteHook)
	for _, d in ipairs(RS:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") then
			log("REMOTELIST", d.ClassName .. " " .. d:GetFullName())
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		log("PLAYER", p.Name .. " team=" .. teamOf(p))
	end
	local c = lp.Character
	if c then
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("LocalScript") or d:IsA("Script") or d:IsA("Tool") or d:IsA("ValueBase") then
				log("CHARTREE", d.ClassName .. " " .. d:GetFullName())
			end
		end
	end
	for _, d in ipairs(lp:WaitForChild("PlayerGui"):GetDescendants()) do
		if d:IsA("LocalScript") then log("GUISCRIPT", d:GetFullName()) end
	end
end)

-- UI
local parent = (gethui and gethui()) or CoreGui
local gui = Instance.new("ScreenGui")
gui.Name = "VDLogger"
gui.ResetOnSpawn = false
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(210, 162)
frame.Position = UDim2.new(0, 20, 0.5, -80)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 24)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -76, 0, 26)
title.Position = UDim2.fromOffset(8, 4)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamMedium
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(230, 230, 230)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "VD Logger | 0 log"
title.Parent = frame

local function btn(text, x, y, w, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, 30)
	b.Position = UDim2.fromOffset(x, y)
	b.BackgroundColor3 = Color3.fromRGB(45, 45, 48)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.Gotham
	b.TextSize = 12
	b.TextColor3 = Color3.fromRGB(220, 220, 220)
	b.Text = text
	b.AutoButtonColor = false
	b.Parent = frame
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
	b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(68, 68, 72) end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = Color3.fromRGB(45, 45, 48) end)
	b.MouseButton1Click:Connect(function() cb(b) end)
	return b
end

local function dump() return table.concat(logs, "\n") end

btn("Copy", 8, 36, 92, function(b)
	if setclipboard then setclipboard(dump()) b.Text = "Tersalin" else b.Text = "No clipboard" end
	task.delay(1.2, function() b.Text = "Copy" end)
end)
btn("Save File", 110, 36, 92, function(b)
	if writefile then
		writefile("VD_Log_" .. os.time() .. ".txt", dump())
		b.Text = "Tersimpan"
	else
		b.Text = "No writefile"
	end
	task.delay(1.2, function() b.Text = "Save File" end)
end)
btn("Rekam: ON", 8, 76, 194, function(b)
	running = not running
	b.Text = running and "Rekam: ON" or "Rekam: OFF"
	flush()
end)
btn("Clear", 8, 116, 194, function()
	flush()
	logs = {}
	saved = 0
	t0 = os.clock()
end)
-- Tombol header: sembunyi dan tutup
local function hdrBtn(text, xOff, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(26, 22)
	b.Position = UDim2.new(1, xOff, 0, 6)
	b.BackgroundColor3 = Color3.fromRGB(45, 45, 48)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.TextColor3 = Color3.fromRGB(220, 220, 220)
	b.Text = text
	b.AutoButtonColor = false
	b.Parent = frame
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(68, 68, 72) end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = Color3.fromRGB(45, 45, 48) end)
	b.MouseButton1Click:Connect(cb)
	return b
end

-- Pil kecil untuk memunculkan panel lagi
local pill = Instance.new("TextButton")
pill.Size = UDim2.fromOffset(44, 26)
pill.Position = UDim2.new(0, 20, 0.5, -13)
pill.BackgroundColor3 = Color3.fromRGB(22, 22, 24)
pill.BorderSizePixel = 0
pill.Font = Enum.Font.GothamMedium
pill.TextSize = 12
pill.TextColor3 = Color3.fromRGB(230, 230, 230)
pill.Text = "VD"
pill.AutoButtonColor = false
pill.Visible = false
pill.Active = true
pill.Draggable = true
pill.Parent = gui
Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 8)

local function setHidden(h)
	frame.Visible = not h
	pill.Visible = h
end

hdrBtn("-", -62, function() setHidden(true) end)
hdrBtn("X", -32, function()
	closed = true
	flush()
	running = false
	gui:Destroy()
end)
pill.MouseButton1Click:Connect(function() setHidden(false) end)

UIS.InputBegan:Connect(function(i, gpe)
	if not gpe and i.KeyCode == Enum.KeyCode.RightShift and not closed then
		setHidden(frame.Visible)
	end
end)
task.spawn(function()
	while not closed do
		task.wait(0.5)
		if not closed then
			if not gui.Parent then pcall(function() gui.Parent = parent end) end
			title.Text = "VD Logger | " .. #logs .. " log"
		end
	end
end)
-- AUTOSAVE tiap 10 detik, memori dikosongkan kalau sudah 5000 (isi aman di file)
task.spawn(function()
	while not closed do
		task.wait(10)
		flush()
		if appendfile and #logs >= 5000 then logs = {} saved = 0 end
	end
end)
-- simpan terakhir saat teleport, lalu jalankan ulang di tempat baru
lp.OnTeleport:Connect(flush)
local qot = queue_on_teleport or (syn and syn.queue_on_teleport)
if qot then
	pcall(qot, 'if isfile("VD_Main.lua") then loadstring(readfile("VD_Main.lua"))() end')
end
