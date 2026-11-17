using Microsoft.Extensions.Logging;
using Sefiro.TransformationMenu.Common;
using OblivionMP.SDK;
using OblivionMpCSharpMod.Input;
using ReadyM.Cef;
using ReadyM.Cef.Rpc;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Client;

// Transformation menu: Alt+U opens/closes a web page (web/index.html, readym://obmptransform/) listing the creatures.
// In 1.1.0 a page cannot take the mouse during gameplay (web-ui docs), so the menu is keyboard-driven: the page
// takes focus (like the chat), arrows + Enter select, Esc closes. Clicking works where the game already shows the
// cursor. The choice goes to the server with the TransformRequest RPC: same logic as /transform.
[Service]
public sealed partial class TransformMenu(CefHost cef, IInput input, IPlayers players, TransformState state, PackCatalog packs,
    RpcHandlers rpc, ILogger logger)
{
    private const string Host = "obmptransform";
    private ViewportHandle _viewport;
    private BrowserHandle? _page;
    private bool _created;
    private bool _open;

    private void Start()
    {
        var folder = Path.GetDirectoryName(typeof(TransformMenu).Assembly.Location)!;
        cef.RegisterFolder(Host, Path.Combine(folder, "web"));
        // Alt+U: Ctrl in Oblivion is sneak, F5/F6/F8 are already used by DogmaAdmin.
        // It used to be Alt+T: T is "Wait" and the game takes the key before we do. With Polled both menus opened,
        // with UnhandledByUi only the wait menu did (test 2026-11-17). The game does not use U.
        // Polled: with UnhandledByUi Alt+U never arrived either (test 2026-11-17 01:43, no line in the log);
        // Polled is the only way the menu has opened. While typing (chat) the key is ignored.
        input.RegisterKeyBind(ModifierKeys.Alt, Key.U, Toggle);
    }

    private void Toggle()
    {
        if (!_open && !input.CanApplyInput())
        {
            logger.LogInformation("[Transform] Alt+U ignored: a text field or a menu has the keyboard");
            return;
        }
        if (_open) Close();
        else Open();
    }

    private void Open()
    {
        if (!_created) Create();
        _open = true;
        logger.LogInformation("[Transform] menu opened (Alt+U)");
        cef.SetVisible(_viewport, true);
        cef.SetFocused(_viewport, true);
        if (_page is { } page) SendState(page);
    }

    private void Close()
    {
        _open = false;
        cef.SetFocused(_viewport, false);
        cef.SetVisible(_viewport, false);
    }

    private void Create()
    {
        _created = true;
        _viewport = cef.CreateViewport(zOrder: 10);
        cef.SetPlacement(_viewport, ViewportPlacement.Centered(440, 620));
        cef.SetInputMode(_viewport, CefInputMode.Exclusive);
        var browser = cef.CreateBrowser();
        browser.Navigate($"readym://{Host}/");
        cef.Assign(_viewport, browser.Handle);
    }

    private void SendState(BrowserHandle page)
    {
        var me = players.LocalPlayer?.PlayerId;
        var current = me is { } id ? state.CurrentFor(id) : "";
        SendTransformMenuState(page, Creatures.MenuList(packs.MenuEntries), current);
    }

    // The page is loaded (readym.sendTransformMenuReady()).
    [ReceiveFromCef]
    private void OnTransformMenuReady(BrowserHandle page)
    {
        _page = page;
        SendState(page);
    }

    // Choice: the creature name, or "off" to return to normal.
    [ReceiveFromCef]
    private void OnTransformMenuPick(BrowserHandle page, string creature)
    {
        if (creature != "off" && !Creatures.IsKnown(creature)) return;
        logger.LogInformation("[Transform] menu: {Creature}", creature);
        rpc.SendTransformRequest(creature);
        Close();
    }

    [ReceiveFromCef]
    private void OnTransformMenuClose(BrowserHandle page) => Close();

    // Creature list (comma-separated) and current form ("" = normal).
    [SendToCef]
    public partial void SendTransformMenuState(BrowserHandle page, string creatures, string current);
}
