using System.Diagnostics;
using Microsoft.Extensions.Logging;
using Sefiro.AnimationMenu.Common;
using OblivionMP.SDK;
using OblivionMpCSharpMod.Input;
using ReadyM.Cef;
using ReadyM.Cef.Rpc;
using ReadyM.SDK.Attributes;

namespace Sefiro.AnimationMenu.Client;

// The animation menu: Alt+Y opens and closes web/index.html (readym://sefiroanimationmenu/) on the right side of the
// screen; the character, framed by the bench camera, stays on the left. Keyboard and mouse (the Lua shows the game's
// cursor while the menu is open). Every command goes to the Lua on this PC.
[Service]
public sealed partial class AnimMenu(CefHost cef, IInput input, AnimFiles files, ILogger logger)
{
    private const string Host = "sefiroanimationmenu";
    private ViewportHandle _viewport;
    private BrowserHandle? _page;
    private bool _created;
    private bool _open;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private long _nextPollMs;
    private int _listTick;

    private void Start()
    {
        var folder = Path.GetDirectoryName(typeof(AnimMenu).Assembly.Location)!;
        cef.RegisterFolder(Host, Path.Combine(folder, "web"));
        // Alt+Y. UnhandledByUi stops the key here, so it does not reach the game.
        input.RegisterKeyBind(ModifierKeys.Alt, Key.Y, Toggle, KeySource.UnhandledByUi);
    }

    private void Update()
    {
        if (!_open || _page is not { } page) return;
        var now = _clock.ElapsedMilliseconds;
        if (now < _nextPollMs) return;
        _nextPollMs = now + 100;
        if (files.ReadPosIfChanged() is { } pos) SendAnimMenuPos(page, pos);
        if (++_listTick % 2 == 0 && files.ReadListIfChanged() is { } list) SendAnimMenuList(page, list);
    }

    private void Toggle()
    {
        if (_open) Close();
        else Open();
    }

    private void Open()
    {
        if (!_created) Create();
        _open = true;
        cef.SetVisible(_viewport, true);
        cef.SetFocused(_viewport, true);
        files.ForgetList();
        files.ForgetPos();
        files.Push("open");
        files.Push("scan");
    }

    private void Close()
    {
        if (_open) files.Push("close");   // the Lua turns off the bench camera and gives the player back
        _open = false;
        cef.SetFocused(_viewport, false);
        cef.SetVisible(_viewport, false);
    }

    private void Create()
    {
        _created = true;
        _viewport = cef.CreateViewport(zOrder: 10);
        // 560x960: the list, the camera pad and the playback deck
        cef.SetPlacement(_viewport, ViewportPlacement.Pinned(ViewportAlign.End, ViewportAlign.Center, 560, 960, 24));
        cef.SetInputMode(_viewport, CefInputMode.Exclusive);
        var browser = cef.CreateBrowser();
        browser.Navigate($"readym://{Host}/");
        cef.Assign(_viewport, browser.Handle);
    }

    // The page has loaded (readym.sendAnimMenuReady()).
    [ReceiveFromCef]
    private void OnAnimMenuReady(BrowserHandle page)
    {
        _page = page;
        files.ForgetList();
        files.Push("scan");
    }

    [ReceiveFromCef]
    private void OnAnimMenuCommand(BrowserHandle page, string command)
    {
        if (!AnimCommands.IsValid(command)) { logger.LogWarning("[AnimationMenu] invalid command {Command}", command); return; }
        // The target is only the local player and commands stay on this PC. Showing the animation to the other
        // players is planned for a later version.
        files.Push(command);
    }

    [ReceiveFromCef]
    private void OnAnimMenuClose(BrowserHandle page) => Close();

    // The contents of list.txt (written by the Lua).
    [SendToCef]
    public partial void SendAnimMenuList(BrowserHandle page, string list);

    // The animation position for the timeline: "seconds length", or "- -" when nothing is playing.
    [SendToCef]
    public partial void SendAnimMenuPos(BrowserHandle page, string pos);
}
