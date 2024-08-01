-- Fort journal with a multi-line text editor
--@ module = true

local gui = require 'gui'
local widgets = require 'gui.widgets'
local utils = require 'utils'
local json = require 'json'
local text_editor = reqscript('internal/journal/text_editor')
local shifter = reqscript('internal/journal/shifter')
local table_of_contents = reqscript('internal/journal/table_of_contents')

local RESIZE_MIN = {w=32, h=10}

JOURNAL_PERSIST_KEY = 'journal'

journal_config = journal_config or json.open('dfhack-config/journal.json')

JournalWindow = defclass(JournalWindow, widgets.Window)
JournalWindow.ATTRS {
    frame_title='DF Journal',
    resizable=true,
    resize_min=RESIZE_MIN,
    frame_inset={l=0,r=0,t=0,b=0},
    init_text=DEFAULT_NIL,
    init_cursor=1,
    save_layout=true,

    on_text_change=DEFAULT_NIL,
    on_cursor_change=DEFAULT_NIL,
    on_layout_change=DEFAULT_NIL
}

function JournalWindow:init()
    local frame, toc_visible, toc_width = self:loadConfig()

    self.frame = frame and self:sanitizeFrame(frame) or self.frame

    self:addviews({
        table_of_contents.TableOfContents{
            view_id='table_of_contents_panel',
            frame={l=0, w=toc_width, t=0, b=1},
            visible=toc_visible,
            frame_inset={l=0, t=1, b=1, r=1},

            resize_min={w=20},
            resizable=true,
            resize_anchors={l=false, t=false, b=true, r=true},

            on_resize_begin=self:callback('onPanelResizeBegin'),
            on_resize_end=self:callback('onPanelResizeEnd'),

            on_submit=self:callback('onTableOfContentsSubmit')
        },
        shifter.Shifter{
            view_id='shifter',
            frame={l=0, w=1, t=1, b=2},
            collapsed=not toc_visible,
            on_changed = function (collapsed)
                self.subviews.table_of_contents_panel.visible = not collapsed
                self.subviews.table_of_contents_divider.visible = not collapsed

                if not colllapsed then
                    self.subviews.table_of_contents_panel:reload(
                        self.subviews.journal_editor:getText()
                    )
                end

                self:ensurePanelsRelSize()
                self:updateLayout()
            end,
        },
        widgets.Divider{
            frame={l=0,r=0,b=2,h=1},
            frame_style_l=false,
            frame_style_r=false,
            interior_l=true,
        },
        widgets.Divider{
            view_id='table_of_contents_divider',

            frame={l=30,t=0,b=2,w=1},
            visible=toc_visible,

            interior_b=true,
            frame_style_t=false,
        },
        text_editor.TextEditor{
            view_id='journal_editor',
            frame={t=1, b=3, l=25, r=0},
            resize_min={w=30, h=10},
            frame_inset={l=1,r=0},
            init_text=self.init_text,
            init_cursor=self.init_cursor,
            on_text_change=self:callback('onTextChange'),
            on_cursor_change=self:callback('onCursorChange'),
        },
        widgets.Panel{
            frame={l=0,r=0,b=1,h=1},
            frame_inset={l=1,r=1,t=0, w=100},
            subviews={
                widgets.HotkeyLabel{
                    key='CUSTOM_CTRL_O',
                    label='Table of Contents',
                    on_activate=function() self.subviews.shifter:toggle() end
                }
            }
        }
    })

    self.subviews.table_of_contents_panel:reload(self.init_text)
end

function JournalWindow:onInput(keys)
    if (keys.A_MOVE_N_DOWN) then
        local curr_cursor = self.subviews.journal_editor:getCursor()
        local section_index, section = self.subviews.table_of_contents_panel:cursorSection(
            curr_cursor
        )

        if section.line_cursor == curr_cursor then
            self.subviews.table_of_contents_panel:setSelectedSection(
                section_index - 1
            )
            self.subviews.table_of_contents_panel:submit()
        else
            self:onTableOfContentsSubmit(section_index, section)
        end

        return false
    elseif (keys.A_MOVE_S_DOWN) then
        local section_index = self.subviews.table_of_contents_panel:cursorSection(
            self.subviews.journal_editor:getCursor()
        )
        self.subviews.table_of_contents_panel:setSelectedSection(
            section_index + 1
        )
        self.subviews.table_of_contents_panel:submit()

        return false
    end

    return JournalWindow.super.onInput(self, keys)
end

function JournalWindow:sanitizeFrame(frame)
    local w, h = dfhack.screen.getWindowSize()
    local min = RESIZE_MIN
    if frame.t and h - frame.t - (frame.b or 0) < min.h then
        frame.t = h - min.h
        frame.b = 0
    end
    if frame.b and h - frame.b - (frame.t or 0) < min.h then
        frame.b = h - min.h
        frame.t = 0
    end
    if frame.l and w - frame.l - (frame.r or 0) < min.w then
        frame.l = w - min.w
        frame.r = 0
    end
    if frame.r and w - frame.r - (frame.l or 0) < min.w then
        frame.r = w - min.w
        frame.l = 0
    end
    return frame
end

function JournalWindow:saveConfig()
    if not self.save_layout then
        return
    end

    local toc = self.subviews.table_of_contents_panel

    utils.assign(journal_config.data, {
        frame = self.frame,
        toc = {
            width = toc.frame.w,
            visible = toc.visible
        }
    })
    journal_config:write()
end

function JournalWindow:loadConfig()
    if not self.save_layout then
        return nil, false, 25
    end

    local window_frame = copyall(journal_config.data.frame or {})
    local table_of_contents = copyall(journal_config.data.toc or {
        width=20,
        visible=false
    })

    return window_frame, table_of_contents.visible or false, table_of_contents.width or 25
end

function JournalWindow:onPanelResizeBegin()
    self.resizing_panels = true
end

function JournalWindow:onPanelResizeEnd()
    self.resizing_panels = false
    self:ensurePanelsRelSize()

    self:updateLayout()
end

function JournalWindow:onRenderBody(painter)
    if self.resizing_panels then
        self:ensurePanelsRelSize()
        self:updateLayout()
    end

    return JournalWindow.super.onRenderBody(self, painter)
end

function JournalWindow:ensurePanelsRelSize()
    local toc_panel = self.subviews.table_of_contents_panel
    local editor = self.subviews.journal_editor
    local divider = self.subviews.table_of_contents_divider

    toc_panel.frame.w = math.min(
        math.max(toc_panel.frame.w, toc_panel.resize_min.w),
        self.frame.w - editor.resize_min.w
    )
    editor.frame.l = toc_panel.visible and toc_panel.frame.w or 1
    divider.frame.l = editor.frame.l - 1
end

function JournalWindow:preUpdateLayout()
    self:ensurePanelsRelSize()
end

function JournalWindow:postUpdateLayout()
    self:saveConfig()
end

function JournalWindow:onCursorChange(cursor)
    local section_index = self.subviews.table_of_contents_panel:cursorSection(
        cursor
    )
    self.subviews.table_of_contents_panel:setSelectedSection(section_index)

    if self.on_cursor_change ~= nil then
        self.on_cursor_change(cursor)
    end
end

function JournalWindow:onTextChange(text)
    self.subviews.table_of_contents_panel:reload(text)

    if self.on_text_change ~= nil then
        self.on_text_change(text)
    end
end

function JournalWindow:onTableOfContentsSubmit(ind, section)
    self.subviews.journal_editor:setCursor(section.line_cursor)
    self.subviews.journal_editor:scrollToCursor(section.line_cursor)
end

JournalScreen = defclass(JournalScreen, gui.ZScreen)
JournalScreen.ATTRS {
    focus_path='journal',
    save_on_change=true,
    save_layout=true,
    save_prefix=''
}

function JournalScreen:init()
    local context = self:loadContext()

    self:addviews{
        JournalWindow{
            view_id='journal_window',
            frame={w=65, h=45},
            resize_min={w=50, h=20},
            resizable=true,

            save_layout=self.save_layout,

            init_text=context.text[1],
            init_cursor=context.cursor[1],

            on_text_change=self:callback('saveContext'),
            on_cursor_change=self:callback('saveContext')
        },
    }
end

function JournalScreen:loadContext()
    local site_data = dfhack.persistent.getSiteData(
        self.save_prefix .. JOURNAL_PERSIST_KEY
    ) or {}
    site_data.text = site_data.text or {''}
    site_data.cursor = site_data.cursor or {#site_data.text[1] + 1}

    return site_data
end

function JournalScreen:onTextChange(text)
    self:saveContext(text)
end

function JournalScreen:saveContext()
    if self.save_on_change and dfhack.isWorldLoaded() then
        local text = self.subviews.journal_editor:getText()
        local cursor = self.subviews.journal_editor:getCursor()

        dfhack.persistent.saveSiteData(
            self.save_prefix .. JOURNAL_PERSIST_KEY,
            {text={text}, cursor={cursor}}
        )
    end
end

function JournalScreen:onDismiss()
    view = nil
end

function main(options)
    if not dfhack.isMapLoaded() or not dfhack.world.isFortressMode() then
        qerror('journal requires a fortress map to be loaded')
    end

    local save_layout = options and options.save_layout
    local save_on_change = options and options.save_on_change

    view = view and view:raise() or JournalScreen{
        save_prefix=options and options.save_prefix or '',
        save_layout=save_layout == nil and true or save_layout,
        save_on_change=save_on_change == nil and true or save_on_change,
    }:show()
end

if not dfhack_flags.module then
    main()
end
