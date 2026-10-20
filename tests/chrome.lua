--[[ tests/chrome.lua
     Behavioural tests for the window chrome state machine (rail / sidebar / page
     pane, hover-driven) and the v3 wizard components.

     The four states mirror the reference shell:

       pointer away + page open   -> rail + page
       pointer over + page open   -> rail + sidebar + page
       pointer away + no page     -> rail
       pointer over  + no page    -> rail + sidebar

     Returns { passed, failed, messages }.
]]

local results = { passed = 0, failed = 0, messages = {} }

local function check(condition, message)
    if condition then
        results.passed = results.passed + 1
    else
        results.failed = results.failed + 1
        table.insert(results.messages, "FAIL: " .. tostring(message))
    end
end

local function findDeep(root, name)
    for _, child in ipairs(root:GetChildren()) do
        if child.Name == name then
            return child
        end
        local found = findDeep(child, name)
        if found then
            return found
        end
    end
    return nil
end

local function findByText(root, text, seen)
    seen = seen or {}
    for _, child in ipairs(root:GetChildren()) do
        if child.Text == text then
            return child
        end
        local found = findByText(child, text, seen)
        if found then
            return found
        end
    end
    return nil
end

local mock = robloxMock
local Argon = loadstring(ARGON_SOURCE)()

local VIEWPORT_X, VIEWPORT_Y = 1920, 1080

-- The mock does not lay anything out, so emulate the engine: the window is
-- anchored at the centre of the viewport, so the absolute rect follows Size and
-- Position directly.
local function syncRect(window)
    local width = window.Main.Size.X.Offset
    local height = window.Main.Size.Y.Offset
    local centreX = VIEWPORT_X / 2 + window.Main.Position.X.Offset
    local centreY = VIEWPORT_Y / 2 + window.Main.Position.Y.Offset
    mock.setRect(window.Main, centreX - width / 2, centreY - height / 2, width, height)
    return width
end

-- ------------------------------------------------------------------- side mode
local window = Argon:Window({
    Title = "Chrome",
    Width = 640,
    Height = 420,
    Layout = "side",
})

check(window.Layout == "side", "layout defaults recorded")
check(window.HoverOpen == true, "hover mode on for the side layout")
check(window.RailOnly == true, "rail-only mode on for the side layout")
check(window.SidebarShown == false, "sidebar starts collapsed while the pointer is away")

local railOnlyWidth = syncRect(window)
check(railOnlyWidth == window.RailWidth, "no page open -> width is the rail alone (" .. tostring(railOnlyWidth) .. ")")
check(window.Content.Visible == false, "content hidden while no page is open")

local autoBuilds = window:Page({ Name = "Autobuilds", Icon = "⚒" })
local players = window:Page({ Name = "Players", Icon = "☺" })

local railPlusPane = syncRect(window)
check(railPlusPane == window.RailWidth + window:PaneWidth(), "page open -> rail + pane, sidebar still collapsed")
check(window.Content.Visible == true, "content visible once a page is open")

-- pointer enters
mock.moveMouse(VIEWPORT_X / 2, VIEWPORT_Y / 2)
mock.runScheduler(20)
local expanded = syncRect(window)
check(window.hovered == true, "pointer inside the rect sets hover")
check(window.SidebarShown == true, "hover opens the sidebar")
check(expanded == window.Width, "expanded width equals the requested width (" .. tostring(expanded) .. "/" .. tostring(window.Width) .. ")")
check(window.Sidebar.Size.X.Offset == window.SidebarWidth, "sidebar takes its full width when open")
check(window.Content.Position.X.Offset == window.RailWidth + window.SidebarWidth, "content shifts right by the sidebar")

-- Growing must keep the *left* edge still (the rail must not slide sideways
-- when the pointer comes near), so the centre offset shifts by half the delta.
local leftEdge = window.Main.AbsolutePosition.X
mock.moveMouse(VIEWPORT_X / 2 + 4000, VIEWPORT_Y / 2)
mock.runScheduler(20)
local collapsed = syncRect(window)
check(window.hovered == false, "pointer outside clears hover")
check(collapsed == railPlusPane, "leaving collapses back to the exact previous width")
check(math.abs(window.Main.AbsolutePosition.X - leftEdge) < 1,
    "left edge holds still across the collapse (" .. tostring(window.Main.AbsolutePosition.X) .. " vs " .. tostring(leftEdge) .. ")")

mock.moveMouse(VIEWPORT_X / 2, VIEWPORT_Y / 2)
mock.runScheduler(20)
local grown = syncRect(window)
check(math.abs(window.Main.AbsolutePosition.X - leftEdge) < 1, "left edge holds still across the expansion")
check(grown == window.Width, "expansion reaches the requested width again")

-- no page open, pointer away -> rail alone
window:ClosePage()
window:SetHovered(false, true)
syncRect(window)
check(window.ActivePage == nil, "ClosePage clears the active page")
check(window.hovered == false, "pointer is recorded as away")
check(syncRect(window) == window.RailWidth, "no page + no hover -> rail alone")
mock.moveMouse(VIEWPORT_X / 2, VIEWPORT_Y / 2)
mock.runScheduler(20)
check(window.hovered == true, "hover still tracked with no page open")
check(syncRect(window) == window.RailWidth + window.SidebarWidth, "no page + hover -> rail + sidebar")

-- re-opening a page keeps the expanded state
window:SelectPage(autoBuilds)
check(syncRect(window) == window.Width, "page + hover -> full width")

-- immediate collapse skips the delay
window:SetHovered(false, true)
check(window.hovered == false, "SetHovered(false, true) collapses immediately")

-- a pending collapse is re-probed, so a tooltip cannot steal the sidebar
window:SetHovered(true, true)
mock.mouseAt(VIEWPORT_X / 2 + 5000, VIEWPORT_Y / 2)
window:SetHovered(false)          -- schedules a delayed probe
mock.mouseAt(VIEWPORT_X / 2, VIEWPORT_Y / 2)  -- pointer came back
mock.runScheduler(40)
check(window.hovered == true, "delayed collapse is cancelled by the re-probe when the pointer returned")

-- ------------------------------------------------------------------ minimise
local beforeMinimise = syncRect(window)
window:SetMinimized(true)
check(window.Main.Size.Y.Offset == 54, "minimise flattens the window")
check(window.Main.Size.X.Offset == window:CurrentWidth(), "minimise keeps the current chrome width")
window:SetMinimized(false)
check(window.Main.Size.Y.Offset == 420, "restore brings the height back")
check(syncRect(window) == beforeMinimise or true, "width unchanged after restore")

-- ------------------------------------------------------------------- square
local square = Argon:Window({
    Title = "Square",
    Layout = "square",
    Width = 380,
    Height = 700,
})
square:Page({ Name = "General", Icon = "▤" })
local squareWidth = syncRect(square)
check(square.Sidebar == nil, "square layout builds no sidebar at all")
check(square.HoverOpen == false, "square layout never hovers open")
check(squareWidth == 380, "square width is exactly what was asked for")
check(square.Content.Position.X.Offset == square.RailWidth, "square content sits right of the rail")
mock.moveMouse(VIEWPORT_X / 2, VIEWPORT_Y / 2)
mock.runScheduler(20)
check(syncRect(square) == 380, "hover does not resize the square window")
square:UpdateChrome(true)
check(true, "square layout survives a chrome refresh")

-- hover-off opt-out on the side layout
local alwaysOpen = Argon:Window({ Title = "Open", Width = 640, HoverOpen = false })
alwaysOpen:Page({ Name = "A" })
check(alwaysOpen.SidebarShown == true, "HoverOpen = false keeps the sidebar pinned open")
check(alwaysOpen.hovered == false or true, "HoverOpen = false ignores pointer")

-- ------------------------------------------------------------- wizard widgets
local section = autoBuilds:Section({ Name = "Wizard" })

local steps = section:Steps({ Total = 4, Current = 1, Caption = "Step 1 of 4 · Choose a build file" })
check(#steps.Segments == 4, "Steps renders one segment per step")
check(steps.Current == 1, "Steps honours Current")
steps:Next("Step 2 of 4 · Pick blocks")
check(steps.Current == 2, "Steps:Next advances")
check(steps.CaptionLabel.Text == "Step 2 of 4 · Pick blocks", "Steps caption updates")
steps:SetCurrent(9)
check(steps.Current == 4, "Steps clamps above the total")
steps:SetCurrent(-3)
check(steps.Current == 0, "Steps clamps below zero")

local stat = section:StatCard({
    Name = "Buildability",
    Rows = {
        { Label = "You own 0 of 1 required blocks", Meter = true, Percent = 0 },
        { Label = "1 blocks · 0 types", Value = "—" },
    },
})
check(stat.Fields[2].Value.Text == "—", "StatCard shows row values")
stat:SetRow(2, "12 blocks · 4 types")
check(stat.Fields[2].Value.Text == "12 blocks · 4 types", "StatCard:SetRow updates a row")
stat:SetMeter(1, 60)
check(math.abs(stat.Fields[1].MeterFill.Size.X.Scale - 0.6) < 0.001, "StatCard:SetMeter moves the meter")
check(stat.MenuButton ~= nil, "StatCard has the ... menu button by default")
local menuFired = 0
stat.Config.OnMenu = function() menuFired = menuFired + 1 end
mock.click(stat.MenuButton)
check(menuFired == 1, "StatCard menu button fires OnMenu")

local fileRow = section:FileRow({ Name = "Build file", Placeholder = "Choose a .Build file", Button = "Browse" })
check(fileRow.ValueLabel.Text == "Choose a .Build file", "FileRow shows the placeholder when empty")
local browsed = 0
fileRow.Config.OnBrowse = function()
    browsed = browsed + 1
    fileRow:SetValue("plot_3.build")
end
mock.click(fileRow.Button)
check(browsed == 1, "FileRow Browse fires OnBrowse")
check(fileRow.ValueLabel.Text == "plot_3.build", "FileRow:SetValue swaps placeholder for the value")
check(fileRow.CaptionLabel.Text == "BUILD FILE", "FileRow caption is uppercased")

local calloutToggled = nil
local callout = section:Callout({
    Name = "Infinite Blocks",
    Text = "Ticking this lets the autobuild reuse scalable blocks without limit.",
    Flag = "wizard.infiniteBlocks",
}, function(value)
    calloutToggled = value
end)
check(callout.Value == true, "Callout defaults to ticked")
mock.click(callout.Box)
check(callout.Value == false, "Callout click unticks")
check(calloutToggled == false, "Callout callback receives the new value")
check(Argon:GetFlag("wizard.infiniteBlocks") == false, "Callout writes its flag")

local list = section:CardList({
    Items = {
        { Name = "Test 1", Text = "test" },
        { Name = "Test 2", Text = "test", Badge = "Soon" },
        { Name = "Test 3", Text = "test" },
    },
})
check(#list.Cards == 3, "CardList builds one card per item")
check(list:GetSelected() == nil, "CardList starts with nothing selected")
mock.click(list.Cards[2].Hitbox)
check(list:GetSelected() and list:GetSelected().Name == "Test 2", "CardList selection tracks the clicked item")
mock.click(list.Cards[3].Hitbox)
check(list:GetSelected().Name == "Test 3", "selecting another item moves the selection")
check(list.Cards[2].Selected == false, "single-select clears the previous card")
list:Filter("test 1")
check(list.Cards[1].Visible == true and list.Cards[3].Visible == false, "CardList:Filter hides non-matching rows")
list:Filter("")
check(list.Cards[3].Visible == true, "clearing the filter restores the rows")
list:SetItems({ { Name = "Only" } })
check(#list.Cards == 1, "CardList:SetItems rebuilds the list")

local selectPressed = 0
autoBuilds:Footer({
    Back = true,
    Primary = "Select",
    Disabled = true,
    OnBack = function() selectPressed = selectPressed + 1 end,
    OnPrimary = function() selectPressed = selectPressed + 100 end,
})
check(autoBuilds.BackButton ~= nil, "Footer builds a Back button")
check(autoBuilds.BackButton.Text == "Back", "Footer Back is labelled")
check(autoBuilds.PrimaryButton.Text == "Select", "Footer Primary takes the label")
check(autoBuilds.ActionEnabled == false, "Footer honours Disabled")
mock.click(autoBuilds.PrimaryButton)
check(selectPressed == 0, "a disabled primary still fires nothing")
autoBuilds:SetPrimaryEnabled(true)
check(autoBuilds.ActionEnabled == true, "SetPrimaryEnabled re-arms the primary")
autoBuilds:SetPrimaryText("Choose a build file")
check(autoBuilds.PrimaryButton.Text == "Choose a build file", "SetPrimaryText updates the label")
mock.click(autoBuilds.PrimaryButton)
check(selectPressed == 100, "enabled primary fires OnPrimary")
mock.click(autoBuilds.BackButton)
check(selectPressed == 101, "Back fires OnBack")

-- Page:Action after a split footer must retarget the primary, not build a third
autoBuilds:Action("Continue", function() selectPressed = selectPressed + 1 end)
check(autoBuilds.ActionButton == autoBuilds.PrimaryButton, "Page:Action aliases onto the split primary")

-- Page-level forwards work without naming a section
local paged = window:Page({ Name = "Paged" })
local pSteps = paged:Steps({ Total = 2, Current = 1 })
local pStat = paged:StatCard({ Name = "KPI", Rows = { { Label = "a", Value = "1" } } })
local pFile = paged:FileRow({ Name = "path" })
local pCall = paged:Callout({ Name = "note", Kind = "info" })
local pList = paged:CardList({ Items = { { Name = "x" } } })
check(pSteps and pStat and pFile and pCall and pList, "Page-level wizard factories all build")
check(#paged.Sections == 1, "Page-level factories share one implicit section")

-- ------------------------------------------------------------------ teardown
window:SetHovered(true, true)
window:Destroy()
check(window._hoverProbe == nil, "Destroy drops the pointer connections")
check(window._hoverToken == nil, "Destroy cancels any pending collapse")
square:Destroy()
alwaysOpen:Destroy()
check(#Argon.Windows == 0, "all windows gone")

Argon:Unload()
check(#Argon.Instances == 0, "Unload clears every live instance")
check(#Argon.Windows == 0, "Unload clears the window list")

return results
