--[[ examples/wizard.lua
     The v3 shell shapes, side by side.

     * a "square" window  : rail + page, one narrow column, no sidebar
     * a "side"   window  : rail + sidebar + page, where the sidebar only opens
                            while the pointer is over the window, and the window
                            collapses to the rail alone when no page is open
     * a selectable card list with a footer button that stays locked until you
       pick something
     * a 4-step wizard: step rail, file picker, stat card, checkbox callout and a
       Back / Continue footer

     Run it in an executor. RightShift toggles the square window.
]]

local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()

-- ============================================================================
-- square window: general page with selectable items
-- ============================================================================

local Square = Argon:Window({
    Title = "Argon",
    Subtitle = "square",
    Layout = "square",
    Width = 380,
    Height = 560,
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightShift,
})

local General = Square:Page({ Name = "General", Icon = "▤" })
General:Search({ Placeholder = "Search features" })
General:Pills({ "All", "Free", "Premium" })

-- Declared before the list so the callbacks below can close over it (a local is
-- not in scope inside its own initializer).
local Footer

local Items = General:CardList({
    Section = "Features",
    Select = true,
    PlaceholderGlyph = "▦",
    Items = {
        { Name = "Test 1", Text = "test" },
        { Name = "Test 2", Text = "test", Badge = "Soon" },
        { Name = "Test 3", Text = "test", Tier = "premium" },
    },
    OnSelect = function(item)
        Square:SetSubtitle("selected · " .. item.Name)
        General:SetPrimaryEnabled(true)
        General:SetPrimaryText("Select " .. item.Name)
    end,
    OnOpen = function(item)
        -- clicking an entry can hand over to a page of its own
        local existing = Square:GetPage(item.Name)
        if not existing then
            local opened = Square:Page({ Name = item.Name, Icon = "▸" })
            opened:Section({ Name = "Options" }):Label({ Text = "Page for " .. item.Name })
        end
        Square:SelectPage(existing or Square:GetPage(item.Name))
    end,
})

-- A sticky footer: the primary button stays locked until a card is picked.
Footer = General:Footer({
    Primary = "Select",
    Disabled = true,
    OnPrimary = function()
        local picked = Items:GetSelected()
        Argon:Notify({
            Title = "Selected",
            Text = picked and ("you picked " .. picked.Name) or "nothing selected",
            Kind = "success",
        })
    end,
})

-- ============================================================================
-- side window: hover-driven sidebar + 4-step wizard
-- ============================================================================

local Side = Argon:Window({
    Title = "luau.pro",
    Subtitle = "side",
    Layout = "side",
    Width = 660,
    Height = 460,
    Theme = "Aqua",
    -- HoverOpen = false, -- pin the sidebar open instead of sliding it in on hover
})

local AutoBuilds = Side:Page({ Name = "Autobuilds", Icon = "⚒", Subtitle = "8 Features" })
AutoBuilds:Search({ Placeholder = "Search features" })
AutoBuilds:Pills({ "All", "Free", "Premium" })

AutoBuilds:CardList({
    Section = "Autobuilds",
    Items = {
        { Name = "Autobuild Classic", Text = "Load .Build files with ease", Selected = true },
        { Name = "Save Build", Text = "Save or steal from others" },
        { Name = "Image Loader", Text = "Load any image from the internet" },
    },
})

local Wizard = Side:Page({ Name = "Autobuild Classic", Icon = "★", Subtitle = "Load a saved build in your plot" })
local WizardSection = Wizard:Section({ Name = "Setup" })

local Steps = WizardSection:Steps({
    Total = 4,
    Current = 1,
    Caption = "Step 1 of 4 · Choose a build file",
})

local BuildFile = WizardSection:FileRow({
    Name = "Build file",
    Placeholder = "Choose a .Build file",
    Button = "Browse",
    OnBrowse = function(row)
        row:SetValue("plot_3.build")
        Steps:Next("Step 2 of 4 · Check blocks")
    end,
})

local Buildability = WizardSection:StatCard({
    Name = "Buildability",
    Rows = {
        { Label = "You own 0 of 1 required blocks", Meter = true, Percent = 0 },
        { Label = "1 blocks · 0 types", Value = "—" },
    },
    OnMenu = function()
        Argon:Notify({ Title = "Buildability", Text = "No extra builds in this slot.", Kind = "info" })
    end,
})

local Infinite = WizardSection:Callout({
    Kind = "check",
    Name = "Infinite Blocks",
    Text = "Ticking this lets the autobuild reuse scalable blocks without limit, as long as you own at least 5 of that type.",
    Flag = "wizard.infiniteBlocks",
})

local WizardFooter = Wizard:Footer({
    Back = true,
    Primary = "Choose a build file",
    Disabled = true,
    OnBack = function()
        Steps:Prev("Step 1 of 4 · Choose a build file")
    end,
    OnPrimary = function()
        Steps:Next("Step 3 of 4 · Place")
        Buildability:SetMeter(1, 100)
        Buildability:SetRow(2, "12 blocks · 4 types")
        Wizard:SetPrimaryText("Run build")
        Argon:Notify({
            Title = "Build ready",
            Text = "Infinite blocks: " .. tostring(Infinite:GetValue()),
            Kind = "success",
        })
    end,
})

-- unlock the footer once a file is chosen
BuildFile:OnChanged(function(value)
    Wizard:SetPrimaryEnabled(value ~= nil)
    if value then
        Wizard:SetPrimaryText("Continue")
    end
end)

Side:SelectPage(AutoBuilds)

return { Square = Square, Side = Side }
