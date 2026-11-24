module matn.ui.shell.trustdialog;

import std.algorithm : max, min, clamp;
import std.conv : to;
import std.path : baseName;
import std.string : strip;

import matn.platform.sdl;
import matn.platform.font;
import matn.ui.grid.cell;
import matn.ui.grid.grid;
import matn.extension.base;
import matn.extension.registry;

/// Styling and layout context for TrustDialogExtension
struct TrustDialogContext
{
    int gridCols;
    int gridRows;
    Color bg;
    Color barBg;
    Color text;
    Color muted;
    Color accent;
    Color border;
    Color activeLine;
    bool isLight = false;
    bool blink = true;
}

class TrustDialogExtension : Extension
{
    bool visible = false;
    string projectPath = "";
    int selectedButton = 0; // 0 = Trust, 1 = Restricted Mode
    int hoveredButton = -1; // -1 = none, 0 = Trust, 1 = Restricted, 2 = Close [x]

    int modalX = 0;
    int modalY = 0;
    int modalW = 0;
    int modalH = 0;

    // Button hitboxes (col range within row)
    struct ButtonRect
    {
        int id; // 0 = Trust, 1 = Restricted, 2 = Close
        int row;
        int leftCol;
        int rightCol;
    }
    private ButtonRect[] buttonRects;

    this()
    {
        super(ExtensionManifest(
            "matn.trustdialog",
            "Workspace Trust Agreement",
            "1.0.0",
            "Matn Core",
            "Modal agreement dialog to confirm workspace trust when opening projects",
            true
        ));
    }

    void open(string path)
    {
        projectPath = path;
        selectedButton = 0; // Default to "Trust Folder & Enable Features"
        hoveredButton = -1;
        visible = true;
    }

    void close()
    {
        visible = false;
        hoveredButton = -1;
    }

    void decide(bool trusted)
    {
        close();
        auto extMgr = ExtensionManager.instance();
        if (extMgr && projectPath.length > 0)
        {
            extMgr.setProjectTrusted(projectPath, trusted);
            extMgr.setProjectTrustDecisionMade(projectPath, true);
        }
    }

    bool handleMouseMove(int col, int row)
    {
        if (!visible) return false;
        int oldHover = hoveredButton;
        hoveredButton = -1;

        foreach (ref btn; buttonRects)
        {
            if (row == btn.row && col >= btn.leftCol && col < btn.rightCol)
            {
                hoveredButton = btn.id;
                break;
            }
        }
        return (oldHover != hoveredButton);
    }

    bool handleMouseDown(int col, int row, TrustDialogContext ctx)
    {
        if (!visible) return false;

        // Click outside closes modal in Restricted Mode
        if (col < modalX || col >= modalX + modalW || row < modalY || row >= modalY + modalH)
        {
            decide(false);
            return true;
        }

        foreach (ref btn; buttonRects)
        {
            if (row == btn.row && col >= btn.leftCol && col < btn.rightCol)
            {
                if (btn.id == 0)
                {
                    decide(true);
                    return true;
                }
                else if (btn.id == 1 || btn.id == 2)
                {
                    decide(false);
                    return true;
                }
            }
        }
        return true;
    }

    bool handleKeyDown(uint key, uint mod, TrustDialogContext ctx)
    {
        if (!visible) return false;

        if (key == SDLK_ESCAPE)
        {
            decide(false); // Restricted Mode on Escape
            return true;
        }
        else if (key == SDLK_RETURN || key == 0x40000058) // Enter or Keypad Enter
        {
            decide(selectedButton == 0);
            return true;
        }
        else if (key == 't' || key == 'T')
        {
            decide(true);
            return true;
        }
        else if (key == 'r' || key == 'R')
        {
            decide(false);
            return true;
        }
        else if (key == SDLK_TAB || key == SDLK_LEFT || key == SDLK_RIGHT)
        {
            selectedButton = (selectedButton == 0) ? 1 : 0;
            return true;
        }
        return false;
    }

    void render(GlyphGrid grid, TrustDialogContext ctx)
    {
        if (!visible) return;

        buttonRects = [];

        // Dimensions: clean, readable, centered
        modalW = min(68, max(52, ctx.gridCols - 4));
        modalH = 13;

        modalX = max(0, (ctx.gridCols - modalW) / 2);
        modalY = max(0, (ctx.gridRows - modalH) / 2);

        bool isLight = ctx.isLight || ctx.bg.isLight;
        Color modalBg = ctx.barBg;
        Color textFg = ctx.text;
        Color mutedFg = ctx.muted;
        Color accentFg = ctx.accent;
        Color borderFg = ctx.border;
        Color trustGreen = Color(80, 250, 123, 255);
        Color untrustPink = Color(255, 121, 198, 255);
        Color warnYellow = Color(241, 250, 140, 255);
        Color badgeBg = isLight ? ctx.barBg.darken(8) : ctx.barBg.lighten(8);

        // 1. Fill modal background
        grid.fillRect(modalX, modalY, modalW, modalH, ' ', CellStyle(textFg, modalBg));

        // 2. Header (Row 0)
        grid.putString(modalX + 2, modalY, "󰌿 TRUST THIS WORKSPACE?"d, CellStyle(warnYellow, modalBg, CellAttr.bold));
        int closeCol = modalX + modalW - 3;
        Color closeFg = (hoveredButton == 2) ? accentFg : mutedFg;
        grid.putString(closeCol, modalY, "[x]"d, CellStyle(closeFg, modalBg));
        buttonRects ~= ButtonRect(2, modalY, closeCol, modalX + modalW);

        // 3. Question (Row 2)
        grid.putString(modalX + 2, modalY + 2, "Do you trust the authors of the files in this folder?"d,
                       CellStyle(textFg, modalBg, CellAttr.bold));

        // 4. Folder Path Pill (Row 3)
        string folderName = baseName(projectPath);
        string displayPath = projectPath;
        int maxPathW = modalW - 14;
        if (displayPath.length > maxPathW && maxPathW > 3)
            displayPath = "..." ~ displayPath[$ - (maxPathW - 3) .. $];

        grid.putString(modalX + 2, modalY + 3, "Folder: "d, CellStyle(mutedFg, modalBg));
        grid.putString(modalX + 10, modalY + 3, to!dstring(displayPath), CellStyle(accentFg, modalBg, CellAttr.bold));

        // 5. Explanatory safety text (Rows 5 & 6)
        grid.putString(modalX + 2, modalY + 5, "Trusting enables language servers (LSP), build tools, and extensions"d,
                       CellStyle(mutedFg, modalBg));
        grid.putString(modalX + 2, modalY + 6, "that can execute code and scripts found in this project."d,
                       CellStyle(mutedFg, modalBg));

        // 6. Action Buttons (Row 9)
        dstring btn0Text = " 󰌾 Trust Folder (Features Enabled) "d;
        dstring btn1Text = " 󰌿 Restricted Mode "d;

        int btnY = modalY + 9;
        int btn0Len = cast(int) btn0Text.length;
        int btn1Len = cast(int) btn1Text.length;
        int totalBtnW = btn0Len + 2 + btn1Len;
        int startBtnX = modalX + (modalW - totalBtnW) / 2;

        int btn0X = startBtnX;
        int btn1X = btn0X + btn0Len + 2;

        bool btn0Active = (selectedButton == 0);
        bool btn0Hover = (hoveredButton == 0);
        Color btn0Bg = btn0Active ? (btn0Hover ? trustGreen.lighten(20) : trustGreen)
                                  : (btn0Hover ? ctx.activeLine.lighten(15) : ctx.activeLine);
        Color btn0Fg = btn0Active ? Color(10, 15, 20, 255) : trustGreen;
        ubyte btn0Attr = CellAttr.bold;

        grid.fillRect(btn0X, btnY, btn0Len, 1, ' ', CellStyle(btn0Fg, btn0Bg));
        grid.putString(btn0X, btnY, btn0Text, CellStyle(btn0Fg, btn0Bg, btn0Attr));
        buttonRects ~= ButtonRect(0, btnY, btn0X, btn0X + btn0Len);

        bool btn1Active = (selectedButton == 1);
        bool btn1Hover = (hoveredButton == 1);
        Color btn1Bg = btn1Active ? (btn1Hover ? untrustPink.lighten(20) : untrustPink)
                                  : (btn1Hover ? ctx.activeLine.lighten(15) : badgeBg);
        Color btn1Fg = btn1Active ? Color(10, 15, 20, 255) : (btn1Hover ? textFg : mutedFg);
        ubyte btn1Attr = btn1Active ? CellAttr.bold : CellAttr.none;

        grid.fillRect(btn1X, btnY, btn1Len, 1, ' ', CellStyle(btn1Fg, btn1Bg));
        grid.putString(btn1X, btnY, btn1Text, CellStyle(btn1Fg, btn1Bg, btn1Attr));
        buttonRects ~= ButtonRect(1, btnY, btn1X, btn1X + btn1Len);

        // 7. Shortcut hints below buttons (Row 11)
        grid.putString(btn0X + 4, modalY + 11, "(Press Enter or 'T')"d, CellStyle(mutedFg, modalBg));
        grid.putString(btn1X + 2, modalY + 11, "(Press Esc or 'R')"d, CellStyle(mutedFg, modalBg));
    }

    void renderReal(SDL_Renderer* renderer, FontEngine font, TrustDialogContext ctx, float padX, float padY)
    {
        // Outline removed
    }
}

unittest
{
    auto dialog = new TrustDialogExtension();
    assert(!dialog.visible);
    dialog.open("/tmp/test_project");
    assert(dialog.visible);
    assert(dialog.projectPath == "/tmp/test_project");
    assert(dialog.selectedButton == 0);

    // Toggle button selection
    TrustDialogContext ctx;
    ctx.gridCols = 80;
    ctx.gridRows = 25;
    ctx.bg = Color(20, 20, 25, 255);
    ctx.barBg = Color(25, 25, 30, 255);
    ctx.text = Color(220, 220, 220, 255);
    ctx.muted = Color(120, 120, 120, 255);
    ctx.accent = Color(80, 250, 123, 255);
    ctx.border = Color(60, 60, 70, 255);
    ctx.activeLine = Color(40, 40, 50, 255);

    dialog.handleKeyDown(SDLK_TAB, 0, ctx);
    assert(dialog.selectedButton == 1);
    dialog.handleKeyDown(SDLK_TAB, 0, ctx);
    assert(dialog.selectedButton == 0);

    // Test grid rendering
    auto grid = new GlyphGrid(80, 25);
    dialog.render(grid, ctx);
    assert(dialog.modalW > 0);
    assert(dialog.modalH > 0);
    assert(dialog.buttonRects.length == 3); // Trust, Restricted, Close

    // Test mouse hover
    typeof(dialog.buttonRects[0]) btn0;
    foreach (b; dialog.buttonRects)
    {
        if (b.id == 0)
        {
            btn0 = b;
            break;
        }
    }
    dialog.handleMouseMove(btn0.leftCol + 1, btn0.row);
    assert(dialog.hoveredButton == 0);
    dialog.handleMouseMove(0, 0);
    assert(dialog.hoveredButton == -1);

    // Test keyboard 'T' decision
    dialog.handleKeyDown('t', 0, ctx);
    assert(!dialog.visible);

    // Reopen and test 'R' decision
    dialog.open("/tmp/test_project");
    assert(dialog.visible);
    dialog.handleKeyDown('r', 0, ctx);
    assert(!dialog.visible);

    // Reopen and test click outside (Restricted)
    dialog.open("/tmp/test_project");
    assert(dialog.visible);
    dialog.handleMouseDown(0, 0, ctx);
    assert(!dialog.visible);

    dialog.close();
    assert(!dialog.visible);
}
