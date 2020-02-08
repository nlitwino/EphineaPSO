-- Imports
local core_mainmenu = require("core_mainmenu")
local cfg = require("XpBar.configuration")
-- TODO move to options
local optionsLoaded, options = pcall(require, "XpBar.options")

local optionsFileName = "addons/XpBar/options.lua"

-- Constants
local _PlayerArray = 0x00A94254
local _PlayerMyIndex = 0x00A9C4F4
local _PLTPointer = 0x00A94878

if optionsLoaded then
    -- If options loaded, make sure we have all those we need
    options.configurationEnableWindow = options.configurationEnableWindow == nil and true or options.configurationEnableWindow
    options.enable = options.enable == nil and true or options.enable
    options.xpEnableWindow = options.xpEnableWindow == nil and true or options.xpEnableWindow
    options.xpNoTitleBar = options.xpNoTitleBar or ""
    options.xpNoResize = options.xpNoResize or ""
    options.xpNoMove = options.xpNoMove or ""
    options.xpTransparent = options.xpTransparent == nil and true or options.xpTransparent
    options.xpEnableInfo = options.xpEnableInfo == nil and true or options.xpEnableInfo
    options.xpEnableInfoLevel = options.xpEnableInfoLevel == nil and true or options.xpEnableInfoLevel
    options.xpEnableInfoTotal = options.xpEnableInfoTotal == nil and true or options.xpEnableInfoTotal
    options.xpEnableInfoTNL = options.xpEnableInfoTNL == nil and true or options.xpEnableInfoTNL
    options.xpBarNoOverlay = options.xpBarNoOverlay == nil and true or options.xpBarNoOverlay
    options.xpBarColor = options.xpBarColor or 0xFFE6B300
    options.xpBarX = options.xpBarX or 50
    options.xpBarY = options.xpBarY or 50
    options.xpBarWidth = options.xpBarWidth or -1
    options.xpBarHeight = options.xpBarHeight or 0
else
    options = 
    {
        configurationEnableWindow = true,
        enable = true,
        xpEnableWindow = true,
        xpNoTitleBar = "",
        xpNoResize = "",
        xpNoMove = "",
        xpTransparent = false,
        xpEnableInfo = true,
        xpEnableInfoLevel = true,
        xpEnableInfoTotal = true,
        xpEnableInfoTNL = true,
        xpBarNoOverlay = false,
        xpBarColor = 0xFFE6B300,
        xpBarX = 50,
        xpBarY = 50,
        xpBarWidth = -1,
        xpBarHeight = 0,
    }
end

local function SaveOptions(options)
    local file = io.open(optionsFileName, "w")
    if file ~= nil then
        io.output(file)

        io.write("return {\n")
        io.write(string.format("    configurationEnableWindow = %s,\n", tostring(options.configurationEnableWindow)))
        io.write(string.format("    enable = %s,\n", tostring(options.enable)))
        io.write("\n")
        io.write(string.format("    xpEnableWindow = %s,\n", tostring(options.xpEnableWindow)))
        io.write(string.format("    xpNoTitleBar = \"%s\",\n", options.xpNoTitleBar))
        io.write(string.format("    xpNoResize = \"%s\",\n", options.xpNoResize))
        io.write(string.format("    xpNoMove = \"%s\",\n", options.xpNoMove))
        io.write(string.format("    xpTransparent = %s,\n", tostring(options.xpTransparent)))
        io.write(string.format("    xpEnableInfo = %s,\n", tostring(options.xpEnableInfo)))
        io.write(string.format("    xpEnableInfoLevel = %s,\n", tostring(options.xpEnableInfoLevel)))
        io.write(string.format("    xpEnableInfoTotal = %s,\n", tostring(options.xpEnableInfoTotal)))
        io.write(string.format("    xpEnableInfoTNL = %s,\n", tostring(options.xpEnableInfoTNL)))
        io.write(string.format("    xpBarNoOverlay = %s,\n", tostring(options.xpBarNoOverlay)))
        io.write(string.format("    xpBarColor = 0x%08X,\n", options.xpBarColor))
        io.write(string.format("    xpBarX = %f,\n", options.xpBarX))
        io.write(string.format("    xpBarY = %f,\n", options.xpBarY))
        io.write(string.format("    xpBarWidth = %f,\n", options.xpBarWidth))
        io.write(string.format("    xpBarHeight = %f,\n", options.xpBarHeight))
        io.write("}\n")

        io.close(file)
    end
end

local function GetColorAsFloats(color)
    color = color or 0xFFFFFFFF

    local a = bit.band(bit.rshift(color, 24), 0xFF) / 255;
    local r = bit.band(bit.rshift(color, 16), 0xFF) / 255;
    local g = bit.band(bit.rshift(color, 8), 0xFF) / 255;
    local b = bit.band(color, 0xFF) / 255;

    return { r = r, g = g, b = b, a = a }
end

local imguiProgressBar = function(progress, color)
    color = color or 0xE6B300FF

    if progress == nil then
        imgui.Text("imguiProgressBar() Invalid progress")
        return
    end

    local overlay = nil
    if options.xpBarNoOverlay then
        overlay = ""
    end

    c = GetColorAsFloats(color)
    imgui.PushStyleColor("PlotHistogram", c.r, c.g, c.b, c.a)
    imgui.ProgressBar(progress, options.xpBarWidth, options.xpBarHeight, overlay)
    imgui.PopStyleColor()
end

local DrawStuff = function()
    local myIndex = pso.read_u32(_PlayerMyIndex)
    local myAddress = pso.read_u32(_PlayerArray + 4 * myIndex)
    local pltData = pso.read_u32(_PLTPointer)

    -- Do the thing only if the pointer is not null
    if myAddress == 0 then
        if options.xpEnableInfo then
            imgui.Text("Player data not found")
        end
    elseif pltData == 0 then
        if options.xpEnableInfo then
            imgui.Text("PLT data not found")
        end
    else
        local myClass = pso.read_u8(myAddress + 0x961)
        local myLevel = pso.read_u32(myAddress + 0xE44)
        local myExp = pso.read_u32(myAddress + 0xE48)

        local pltLevels = pso.read_u32(pltData)
        local pltClass = pso.read_u32(pltLevels + 4 * myClass)

        local thisMaxLevelExp = pso.read_u32(pltClass + 0x0C * myLevel + 0x08)
        local nextMaxLevelexp

        if myLevel < 199 then
            nextMaxLevelexp = pso.read_u32(pltClass + 0x0C * (myLevel + 1) + 0x08)
        else
            nextMaxLevelexp = thisMaxLevelExp
        end

        local thisLevelExp = myExp - thisMaxLevelExp
        local nextLevelexp = nextMaxLevelexp - thisMaxLevelExp
        local currLevelExp = nextMaxLevelexp - myExp
        local levelProgress = 1
        if nextLevelexp ~= 0 then
            levelProgress = thisLevelExp / nextLevelexp
        end

        imguiProgressBar(levelProgress, options.xpBarColor)

        if options.xpEnableInfoLevel then
            imgui.Text(string.format("Lv    : %i", myLevel + 1))
        end
        if options.xpEnableInfoTotal then
            imgui.Text(string.format("Total : %i", myExp))
        end
        if options.xpEnableInfoTNL then
            imgui.Text(string.format("TNL   : %i", currLevelExp))
        end
    end
end

-- Drawing
local function present()
    local changedOptions = false
-- If the addon has never been used, open the config window
    -- and disable the config window setting
    if options.configurationEnableWindow then
        ConfigurationWindow.open = true
        options.configurationEnableWindow = false
    end

    ConfigurationWindow.Update()
    if ConfigurationWindow.changed then
        changedOptions = true
        ConfigurationWindow.changed = false
        SaveOptions(options)
    end

    -- Global enable here to let the configuration window work
    if options.enable == false then
        return
    end

    if options.xpTransparent then
        imgui.PushStyleColor("WindowBg", 0, 0, 0, 0)
    end

    if options.xpEnableWindow then
        if changedOptions == true then
            changedOptions = false
            imgui.SetNextWindowPos(options.xpBarX, options.xpBarY, "Always");
        end
        imgui.Begin("Experience Bar", nil, { options.xpNoTitleBar, options.xpNoResize, options.xpNoMove, "AlwaysAutoResize" })
        DrawStuff();
        imgui.End()
    end

    if options.xpTransparent then
        imgui.PopStyleColor(1)
    end
end

-- Init
local function init()
    ConfigurationWindow = cfg.ConfigurationWindow(options)

    local function mainMenuButtonHandler()
        ConfigurationWindow.open = not ConfigurationWindow.open
    end

    core_mainmenu.add_button("XP Bar", mainMenuButtonHandler)


    return
    {
        name = "Experience Bar",
        version = "1.4",
        author = "tornupgaming",
        description = "Displays your current character experience in a handy visual bar.",
        present = present,
    }
end

-- Exports for other modules
return
{
    __addon =
    {
        init = init
    }
}
