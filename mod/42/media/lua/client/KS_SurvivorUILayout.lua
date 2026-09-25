-- Layout adapters only: character data and actions remain owned by vanilla UI.
local Layout = {}

function Layout.fitView(view)
    local parent = view.parent
    if parent == nil then return end
    local width = math.max(1, parent.width)
    local height = math.max(1, parent.height - (parent.tabHeight or 0))
    view:setWidth(width)
    view:setHeight(height)
    -- Never shrink a scroll extent a vanilla view computed for itself
    -- (skills content height): refits converge instead of fighting it.
    local currentH, currentW = 0, 0
    pcall(function() currentH = view:getScrollHeight() or 0 end)
    pcall(function() currentW = view:getScrollWidth() or 0 end)
    view:setScrollWidth(math.max(width, view.knoxContentWidth or width, currentW))
    view:setScrollHeight(math.max(height, view.knoxContentHeight or height, currentH))
end

function Layout.bindView(view)
    view.setWidthAndParentWidth = function(self, width)
        self.knoxContentWidth = width
        Layout.fitView(self)
    end
    view.setHeightAndParentHeight = function(self, height)
        self.knoxContentHeight = height
        Layout.fitView(self)
    end
    view:setScrollChildren(true)
    -- Vertical only. A horizontal bar object shrinks the vanilla scroll
    -- area on mere presence (getScrollAreaHeight subtracts it), stealing
    -- 17px from every tab and forcing spurious vertical scrollbars.
    view:addScrollBars()
    view:setScrollWithParent(false)
    local prerender, render = view.prerender, view.render
    view.prerender = function(self)
        -- Do not reset native Skills' full scroll extent every frame.
        if self.parent and (self.width ~= self.parent.width
            or self.height ~= math.max(1, self.parent.height - (self.parent.tabHeight or 0))) then
            Layout.fitView(self)
        end
        prerender(self)
        self:setStencilRect(0, 0, self.width, self.height)
    end
    view.render = function(self)
        render(self)
        self:clearStencilRect()
    end
    if view.onMouseWheel == nil then
        view.onMouseWheel = function(self, delta)
            self:setYScroll(self:getYScroll() - delta * 30)
            return true
        end
    end
    Layout.fitView(view)
end

-- Wrap the footer using measured labels; reserve its full height below the list.
function Layout.residentFooter(view, spacing, buttonHeight)
    local controls = {view.viewBtn, view.joinPartyBtn, view.sendHomeBtn, view.jobPicker, view.setJobBtn}
    local available = math.max(1, view.width - spacing * 2)
    local x, row = 0, 0
    local placements = {}
    for _, control in ipairs(controls) do
        local label = control.title or "Automatic"
        local width = math.min(available, math.max(control.knoxPreferredWidth or control.width,
            getTextManager():MeasureStringX(UIFont.Small, label) + 24))
        control.knoxPreferredWidth = control.knoxPreferredWidth or control.width
        if x > 0 and x + width > available then x, row = 0, row + 1 end
        placements[#placements + 1] = {control = control, x = x, row = row, width = width}
        x = x + width + spacing
    end
    local footerHeight = (row + 1) * buttonHeight + row * spacing
    local top = math.max(spacing * 2 + buttonHeight, view.height - spacing - footerHeight)
    view.list:setWidth(available)
    view.list:setHeight(math.max(1, top - spacing * 2))
    for _, placement in ipairs(placements) do
        local control = placement.control
        control:setX(spacing + placement.x)
        control:setY(top + placement.row * (buttonHeight + spacing))
        control:setWidth(placement.width)
        control:setHeight(buttonHeight)
    end
    view:setScrollHeight(top + footerHeight + spacing)
end

return Layout
