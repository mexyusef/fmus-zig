const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;

pub const supported = builtin.os.tag == .windows;

pub const HINSTANCE = windows.HINSTANCE;
pub const HWND = windows.HWND;
pub const HICON = ?*opaque {};
pub const HCURSOR = ?*opaque {};
pub const HBRUSH = ?*opaque {};
pub const HMENU = ?*opaque {};
pub const HDC = ?*opaque {};
pub const HBITMAP = ?*opaque {};
pub const HFONT = ?*opaque {};
pub const HGDIOBJ = ?*opaque {};
pub const HMODULE = windows.HMODULE;
pub const HMONITOR = ?*opaque {};
pub const LPCWSTR = [*:0]const u16;
pub const UINT = windows.UINT;
pub const WPARAM = windows.WPARAM;
pub const LPARAM = windows.LPARAM;
pub const LRESULT = windows.LRESULT;
pub const ATOM = u16;
pub const BOOL = windows.BOOL;
pub const DWORD = windows.DWORD;
pub const COLORREF = DWORD;
pub const WORD = u16;
pub const LONG_PTR = isize;
pub const LONG = i32;
pub const INT = c_int;
pub const SIZE = extern struct {
    cx: LONG,
    cy: LONG,
};
pub const TEXTMETRICW = extern struct {
    tmHeight: LONG,
    tmAscent: LONG,
    tmDescent: LONG,
    tmInternalLeading: LONG,
    tmExternalLeading: LONG,
    tmAveCharWidth: LONG,
    tmMaxCharWidth: LONG,
    tmWeight: LONG,
    tmOverhang: LONG,
    tmDigitizedAspectX: LONG,
    tmDigitizedAspectY: LONG,
    tmFirstChar: u16,
    tmLastChar: u16,
    tmDefaultChar: u16,
    tmBreakChar: u16,
    tmItalic: u8,
    tmUnderlined: u8,
    tmStruckOut: u8,
    tmPitchAndFamily: u8,
    tmCharSet: u8,
};

pub const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
pub const WS_POPUP: DWORD = 0x80000000;
pub const WS_CAPTION: DWORD = 0x00C00000;
pub const WS_SYSMENU: DWORD = 0x00080000;
pub const WS_THICKFRAME: DWORD = 0x00040000;
pub const WS_MINIMIZEBOX: DWORD = 0x00020000;
pub const WS_MAXIMIZEBOX: DWORD = 0x00010000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const CS_HREDRAW: UINT = 0x0002;
pub const CS_VREDRAW: UINT = 0x0001;
pub const CW_USEDEFAULT: INT = @as(INT, @bitCast(@as(u32, 0x80000000)));
pub const SW_SHOW: INT = 5;
pub const SW_MAXIMIZE: INT = 3;
pub const SW_RESTORE: INT = 9;
pub const SWP_NOSIZE: UINT = 0x0001;
pub const SWP_NOMOVE: UINT = 0x0002;
pub const SWP_NOZORDER: UINT = 0x0004;
pub const SWP_FRAMECHANGED: UINT = 0x0020;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_COMMAND: UINT = 0x0111;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_ERASEBKGND: UINT = 0x0014;
pub const WM_SETFOCUS: UINT = 0x0007;
pub const WM_KILLFOCUS: UINT = 0x0008;
pub const WM_ACTIVATE: UINT = 0x0006;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const WM_KEYUP: UINT = 0x0101;
pub const WM_CHAR: UINT = 0x0102;
pub const WM_SYSKEYDOWN: UINT = 0x0104;
pub const WM_SYSKEYUP: UINT = 0x0105;
pub const WM_SYSCHAR: UINT = 0x0106;
pub const VK_SHIFT: INT = 0x10;
pub const VK_CONTROL: INT = 0x11;
pub const VK_MENU: INT = 0x12;
pub const VK_BACK: INT = 0x08;
pub const VK_TAB: INT = 0x09;
pub const VK_RETURN: INT = 0x0D;
pub const VK_ESCAPE: INT = 0x1B;
pub const VK_SPACE: INT = 0x20;
pub const VK_PRIOR: INT = 0x21;
pub const VK_NEXT: INT = 0x22;
pub const VK_END: INT = 0x23;
pub const VK_HOME: INT = 0x24;
pub const VK_LEFT: INT = 0x25;
pub const VK_UP: INT = 0x26;
pub const VK_RIGHT: INT = 0x27;
pub const VK_DOWN: INT = 0x28;
pub const VK_INSERT: INT = 0x2D;
pub const VK_DELETE: INT = 0x2E;
pub const VK_LWIN: INT = 0x5B;
pub const VK_RWIN: INT = 0x5C;
pub const VK_LSHIFT: INT = 0xA0;
pub const VK_RSHIFT: INT = 0xA1;
pub const VK_LCONTROL: INT = 0xA2;
pub const VK_RCONTROL: INT = 0xA3;
pub const VK_LMENU: INT = 0xA4;
pub const VK_RMENU: INT = 0xA5;
pub const VK_OEM_1: INT = 0xBA;
pub const VK_OEM_PLUS: INT = 0xBB;
pub const VK_OEM_COMMA: INT = 0xBC;
pub const VK_OEM_MINUS: INT = 0xBD;
pub const VK_OEM_PERIOD: INT = 0xBE;
pub const VK_OEM_2: INT = 0xBF;
pub const VK_OEM_3: INT = 0xC0;
pub const VK_OEM_4: INT = 0xDB;
pub const VK_OEM_5: INT = 0xDC;
pub const VK_OEM_6: INT = 0xDD;
pub const VK_OEM_7: INT = 0xDE;
pub const WM_MOUSEWHEEL: UINT = 0x020A;
pub const WM_MOUSEMOVE: UINT = 0x0200;
pub const WM_MOUSELEAVE: UINT = 0x02A3;
pub const WM_LBUTTONDOWN: UINT = 0x0201;
pub const WM_LBUTTONUP: UINT = 0x0202;
pub const WM_RBUTTONDOWN: UINT = 0x0204;
pub const WM_RBUTTONUP: UINT = 0x0205;
pub const WM_MBUTTONDOWN: UINT = 0x0207;
pub const WM_MBUTTONUP: UINT = 0x0208;
pub const WM_TIMER: UINT = 0x0113;
pub const WM_SIZE: UINT = 0x0005;
pub const WM_SETICON: UINT = 0x0080;
pub const WM_APP: UINT = 0x8000;
pub const ICON_SMALL: WPARAM = 0;
pub const ICON_BIG: WPARAM = 1;
pub const DT_LEFT: UINT = 0x0000;
pub const DT_TOP: UINT = 0x0000;
pub const DT_WORDBREAK: UINT = 0x0010;
pub const DT_EXPANDTABS: UINT = 0x0040;
pub const DT_NOPREFIX: UINT = 0x0800;
pub const TRANSPARENT: INT = 1;
pub const FIXED_PITCH: DWORD = 0x01;
pub const FF_MODERN: DWORD = 0x30;
pub const CLEARTYPE_QUALITY: DWORD = 5;
pub const DEFAULT_CHARSET: DWORD = 1;
pub const OUT_OUTLINE_PRECIS: DWORD = 8;
pub const CLIP_DEFAULT_PRECIS: DWORD = 0;
pub const FW_NORMAL: INT = 400;
pub const FW_BOLD: INT = 700;
pub const GWL_STYLE: INT = -16;
pub const MF_STRING: UINT = 0x00000000;
pub const MF_SEPARATOR: UINT = 0x00000800;
pub const IMAGE_ICON: UINT = 1;
pub const LR_LOADFROMFILE: UINT = 0x00000010;
pub const LR_DEFAULTSIZE: UINT = 0x00000040;
pub const MONITOR_DEFAULTTONEAREST: DWORD = 0x00000002;
pub const BI_RGB: DWORD = 0;
pub const DIB_RGB_COLORS: UINT = 0;
pub const CF_UNICODETEXT: UINT = 13;
pub const GMEM_MOVEABLE: UINT = 0x0002;
pub const SM_CXSCREEN: INT = 0;
pub const SM_CYSCREEN: INT = 1;
pub const VK_F11: INT = 0x7A;
pub const VK_F10: INT = 0x79;
pub const VK_F12: INT = 0x7B;

pub const Rect = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

pub const Point = extern struct {
    x: LONG,
    y: LONG,
};

pub const Msg = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: Point,
    lPrivate: DWORD,
};

pub const PaintStruct = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: Rect,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

pub const WINDOWPLACEMENT = extern struct {
    length: UINT,
    flags: UINT,
    showCmd: UINT,
    ptMinPosition: Point,
    ptMaxPosition: Point,
    rcNormalPosition: Rect,
};

pub const MONITORINFO = extern struct {
    cbSize: DWORD,
    rcMonitor: Rect,
    rcWork: Rect,
    dwFlags: DWORD,
};

pub const RGBQUAD = extern struct {
    rgbBlue: u8,
    rgbGreen: u8,
    rgbRed: u8,
    rgbReserved: u8,
};

pub const BITMAPINFOHEADER = extern struct {
    biSize: DWORD,
    biWidth: LONG,
    biHeight: LONG,
    biPlanes: WORD,
    biBitCount: WORD,
    biCompression: DWORD,
    biSizeImage: DWORD,
    biXPelsPerMeter: LONG,
    biYPelsPerMeter: LONG,
    biClrUsed: DWORD,
    biClrImportant: DWORD,
};

pub const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]RGBQUAD,
};

pub const WndProc = *const fn (?HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub const WndClassW = extern struct {
    style: UINT,
    lpfnWndProc: WndProc,
    cbClsExtra: c_int,
    cbWndExtra: c_int,
    hInstance: ?HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: HBRUSH,
    lpszMenuName: ?LPCWSTR,
    lpszClassName: LPCWSTR,
};

pub const RegisterClassWFn = *const fn (*const WndClassW) callconv(.winapi) ATOM;
pub const CreateWindowExWFn = *const fn (DWORD, LPCWSTR, LPCWSTR, DWORD, INT, INT, INT, INT, ?HWND, HMENU, ?HINSTANCE, ?*anyopaque) callconv(.winapi) ?HWND;
pub const DefWindowProcWFn = *const fn (?HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;
pub const ShowWindowFn = *const fn (?HWND, INT) callconv(.winapi) BOOL;
pub const DestroyWindowFn = *const fn (?HWND) callconv(.winapi) BOOL;
pub const UpdateWindowFn = *const fn (?HWND) callconv(.winapi) BOOL;
pub const GetMessageWFn = *const fn (*Msg, ?HWND, UINT, UINT) callconv(.winapi) i32;
pub const TranslateMessageFn = *const fn (*const Msg) callconv(.winapi) BOOL;
pub const DispatchMessageWFn = *const fn (*const Msg) callconv(.winapi) LRESULT;
pub const PostQuitMessageFn = *const fn (INT) callconv(.winapi) void;
pub const BeginPaintFn = *const fn (?HWND, *PaintStruct) callconv(.winapi) HDC;
pub const EndPaintFn = *const fn (?HWND, *const PaintStruct) callconv(.winapi) BOOL;
pub const GetClientRectFn = *const fn (?HWND, *Rect) callconv(.winapi) BOOL;
pub const GetWindowRectFn = *const fn (?HWND, *Rect) callconv(.winapi) BOOL;
pub const GetDCFn = *const fn (?HWND) callconv(.winapi) HDC;
pub const ReleaseDCFn = *const fn (?HWND, HDC) callconv(.winapi) INT;
pub const FillRectFn = *const fn (HDC, *const Rect, HBRUSH) callconv(.winapi) INT;
pub const DrawTextWFn = *const fn (HDC, [*]const u16, INT, *Rect, UINT) callconv(.winapi) INT;
pub const SetWindowTextWFn = *const fn (?HWND, LPCWSTR) callconv(.winapi) BOOL;
pub const GetKeyStateFn = *const fn (INT) callconv(.winapi) i16;
pub const SetWindowPosFn = *const fn (?HWND, ?HWND, INT, INT, INT, INT, UINT) callconv(.winapi) BOOL;
pub const SetCaptureFn = *const fn (?HWND) callconv(.winapi) ?HWND;
pub const ReleaseCaptureFn = *const fn () callconv(.winapi) BOOL;
pub const SetWindowLongPtrWFn = *const fn (?HWND, INT, isize) callconv(.winapi) isize;
pub const GetWindowLongPtrWFn = *const fn (?HWND, INT) callconv(.winapi) isize;
pub const GetWindowPlacementFn = *const fn (?HWND, *WINDOWPLACEMENT) callconv(.winapi) BOOL;
pub const SetWindowPlacementFn = *const fn (?HWND, *const WINDOWPLACEMENT) callconv(.winapi) BOOL;
pub const MonitorFromWindowFn = *const fn (?HWND, DWORD) callconv(.winapi) HMONITOR;
pub const GetMonitorInfoWFn = *const fn (HMONITOR, *MONITORINFO) callconv(.winapi) BOOL;
pub const MonitorEnumProc = *const fn (HMONITOR, HDC, ?*Rect, LPARAM) callconv(.winapi) BOOL;
pub const EnumDisplayMonitorsFn = *const fn (HDC, ?*const Rect, MonitorEnumProc, LPARAM) callconv(.winapi) BOOL;
pub const TRACKMOUSEEVENT = extern struct {
    cbSize: DWORD,
    dwFlags: DWORD,
    hwndTrack: ?HWND,
    dwHoverTime: DWORD,
};
pub const TME_LEAVE: DWORD = 0x00000002;
pub const TrackMouseEventFn = *const fn (*TRACKMOUSEEVENT) callconv(.winapi) BOOL;
pub const GetSystemMetricsFn = *const fn (INT) callconv(.winapi) INT;
pub const CreateMenuFn = *const fn () callconv(.winapi) HMENU;
pub const AppendMenuWFn = *const fn (HMENU, UINT, usize, ?LPCWSTR) callconv(.winapi) BOOL;
pub const SetMenuFn = *const fn (?HWND, HMENU) callconv(.winapi) BOOL;
pub const DrawMenuBarFn = *const fn (?HWND) callconv(.winapi) BOOL;
pub const PostMessageWFn = *const fn (?HWND, UINT, WPARAM, LPARAM) callconv(.winapi) BOOL;
pub const DestroyMenuFn = *const fn (HMENU) callconv(.winapi) BOOL;
pub const LoadImageWFn = *const fn (?HINSTANCE, LPCWSTR, UINT, INT, INT, UINT) callconv(.winapi) ?*opaque {};
pub const SendMessageWFn = *const fn (?HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;
pub const OpenClipboardFn = *const fn (?HWND) callconv(.winapi) BOOL;
pub const CloseClipboardFn = *const fn () callconv(.winapi) BOOL;
pub const EmptyClipboardFn = *const fn () callconv(.winapi) BOOL;
pub const SetClipboardDataFn = *const fn (UINT, ?windows.HANDLE) callconv(.winapi) ?windows.HANDLE;
pub const GetClipboardDataFn = *const fn (UINT) callconv(.winapi) ?windows.HANDLE;
pub const IsClipboardFormatAvailableFn = *const fn (UINT) callconv(.winapi) BOOL;

pub const CreateSolidBrushFn = *const fn (COLORREF) callconv(.winapi) HBRUSH;
pub const DeleteObjectFn = *const fn (HGDIOBJ) callconv(.winapi) BOOL;
pub const SetTextColorFn = *const fn (HDC, COLORREF) callconv(.winapi) COLORREF;
pub const SetBkModeFn = *const fn (HDC, INT) callconv(.winapi) INT;
pub const SelectObjectFn = *const fn (HDC, HGDIOBJ) callconv(.winapi) HGDIOBJ;
pub const CreateFontWFn = *const fn (INT, INT, INT, INT, INT, DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, LPCWSTR) callconv(.winapi) HFONT;
pub const ExtTextOutWFn = *const fn (HDC, INT, INT, UINT, ?*const Rect, [*]const u16, UINT, ?*const INT) callconv(.winapi) BOOL;
pub const CreateCompatibleDCFn = *const fn (HDC) callconv(.winapi) HDC;
pub const CreateCompatibleBitmapFn = *const fn (HDC, INT, INT) callconv(.winapi) ?*opaque {};
pub const DeleteDCFn = *const fn (HDC) callconv(.winapi) BOOL;
pub const BitBltFn = *const fn (HDC, INT, INT, INT, INT, HDC, INT, INT, DWORD) callconv(.winapi) BOOL;
pub const GetDIBitsFn = *const fn (HDC, HBITMAP, UINT, UINT, ?*anyopaque, *BITMAPINFO, UINT) callconv(.winapi) INT;
pub const GetTextMetricsWFn = *const fn (HDC, *TEXTMETRICW) callconv(.winapi) BOOL;
pub const GetTextExtentPoint32WFn = *const fn (HDC, [*]const u16, INT, *SIZE) callconv(.winapi) BOOL;
pub const GetGlyphIndicesWFn = *const fn (HDC, [*]const u16, INT, [*]u16, DWORD) callconv(.winapi) DWORD;
pub const GGI_MARK_NONEXISTING_GLYPHS: DWORD = 0x0001;
pub const ETO_CLIPPED: UINT = 0x0004;

pub const User32 = struct {
    register_class_w: RegisterClassWFn,
    create_window_ex_w: CreateWindowExWFn,
    def_window_proc_w: DefWindowProcWFn,
    show_window: ShowWindowFn,
    destroy_window: DestroyWindowFn,
    update_window: UpdateWindowFn,
    get_message_w: GetMessageWFn,
    translate_message: TranslateMessageFn,
    dispatch_message_w: DispatchMessageWFn,
    post_quit_message: PostQuitMessageFn,
    begin_paint: BeginPaintFn,
    end_paint: EndPaintFn,
    get_client_rect: GetClientRectFn,
    get_window_rect: GetWindowRectFn,
    get_dc: GetDCFn,
    release_dc: ReleaseDCFn,
    fill_rect: FillRectFn,
    draw_text_w: DrawTextWFn,
    set_window_text_w: SetWindowTextWFn,
    get_key_state: GetKeyStateFn,
    set_window_pos: SetWindowPosFn,
    set_capture: SetCaptureFn,
    release_capture: ReleaseCaptureFn,
    set_window_long_ptr_w: SetWindowLongPtrWFn,
    get_window_long_ptr_w: GetWindowLongPtrWFn,
    get_window_placement: GetWindowPlacementFn,
    set_window_placement: SetWindowPlacementFn,
    monitor_from_window: MonitorFromWindowFn,
    get_monitor_info_w: GetMonitorInfoWFn,
    enum_display_monitors: EnumDisplayMonitorsFn,
    track_mouse_event: TrackMouseEventFn,
    get_system_metrics: GetSystemMetricsFn,
    create_menu: CreateMenuFn,
    append_menu_w: AppendMenuWFn,
    set_menu: SetMenuFn,
    draw_menu_bar: DrawMenuBarFn,
    post_message_w: PostMessageWFn,
    destroy_menu: DestroyMenuFn,
    load_image_w: LoadImageWFn,
    send_message_w: SendMessageWFn,
    invalidate_rect: InvalidateRectFn,
    set_timer: SetTimerFn,
    kill_timer: KillTimerFn,
};

pub const Gdi32 = struct {
    create_solid_brush: CreateSolidBrushFn,
    delete_object: DeleteObjectFn,
    set_text_color: SetTextColorFn,
    set_bk_mode: SetBkModeFn,
    select_object: SelectObjectFn,
    create_font_w: CreateFontWFn,
    ext_text_out_w: ExtTextOutWFn,
    text_out_w: TextOutWFn,
    create_compatible_dc: CreateCompatibleDCFn,
    create_compatible_bitmap: CreateCompatibleBitmapFn,
    delete_dc: DeleteDCFn,
    bit_blt: BitBltFn,
    get_di_bits: GetDIBitsFn,
    get_text_metrics_w: GetTextMetricsWFn,
    get_text_extent_point32_w: GetTextExtentPoint32WFn,
    get_glyph_indices_w: GetGlyphIndicesWFn,
};

pub const InvalidateRectFn = *const fn (?HWND, ?*const Rect, BOOL) callconv(.winapi) BOOL;
pub const SetTimerFn = *const fn (?HWND, usize, UINT, ?*const anyopaque) callconv(.winapi) usize;
pub const KillTimerFn = *const fn (?HWND, usize) callconv(.winapi) BOOL;
pub const TextOutWFn = *const fn (HDC, INT, INT, [*]const u16, INT) callconv(.winapi) BOOL;
pub const GlobalAllocFn = *const fn (UINT, usize) callconv(.winapi) ?windows.HANDLE;
pub const GlobalLockFn = *const fn (?windows.HANDLE) callconv(.winapi) ?*anyopaque;
pub const GlobalUnlockFn = *const fn (?windows.HANDLE) callconv(.winapi) BOOL;
pub const GlobalFreeFn = *const fn (?windows.HANDLE) callconv(.winapi) ?windows.HANDLE;

pub const Api = struct {
    user32_module: HMODULE,
    gdi32_module: HMODULE,
    kernel32_module: HMODULE,
    user32: User32,
    gdi32: Gdi32,
    open_clipboard: OpenClipboardFn,
    close_clipboard: CloseClipboardFn,
    empty_clipboard: EmptyClipboardFn,
    set_clipboard_data: SetClipboardDataFn,
    get_clipboard_data: GetClipboardDataFn,
    is_clipboard_format_available: IsClipboardFormatAvailableFn,
    global_alloc: GlobalAllocFn,
    global_lock: GlobalLockFn,
    global_unlock: GlobalUnlockFn,
    global_free: GlobalFreeFn,

    pub fn load() !Api {
        if (!supported) return error.UnsupportedPlatform;

        const user32_name: [*:0]const u16 = &[_:0]u16{ 'u', 's', 'e', 'r', '3', '2', '.', 'd', 'l', 'l' };
        const gdi32_name: [*:0]const u16 = &[_:0]u16{ 'g', 'd', 'i', '3', '2', '.', 'd', 'l', 'l' };
        const kernel32_name: [*:0]const u16 = &[_:0]u16{ 'k', 'e', 'r', 'n', 'e', 'l', '3', '2', '.', 'd', 'l', 'l' };
        const user32_module = windows.kernel32.LoadLibraryW(user32_name) orelse return error.LoadUser32Failed;
        const gdi32_module = windows.kernel32.LoadLibraryW(gdi32_name) orelse return error.LoadGdi32Failed;
        const kernel32_module = windows.kernel32.LoadLibraryW(kernel32_name) orelse return error.LoadKernel32Failed;

        return .{
            .user32_module = user32_module,
            .gdi32_module = gdi32_module,
            .kernel32_module = kernel32_module,
            .user32 = .{
                .register_class_w = try loadFn(user32_module, RegisterClassWFn, "RegisterClassW"),
                .create_window_ex_w = try loadFn(user32_module, CreateWindowExWFn, "CreateWindowExW"),
                .def_window_proc_w = try loadFn(user32_module, DefWindowProcWFn, "DefWindowProcW"),
                .show_window = try loadFn(user32_module, ShowWindowFn, "ShowWindow"),
                .destroy_window = try loadFn(user32_module, DestroyWindowFn, "DestroyWindow"),
                .update_window = try loadFn(user32_module, UpdateWindowFn, "UpdateWindow"),
                .get_message_w = try loadFn(user32_module, GetMessageWFn, "GetMessageW"),
                .translate_message = try loadFn(user32_module, TranslateMessageFn, "TranslateMessage"),
                .dispatch_message_w = try loadFn(user32_module, DispatchMessageWFn, "DispatchMessageW"),
                .post_quit_message = try loadFn(user32_module, PostQuitMessageFn, "PostQuitMessage"),
                .begin_paint = try loadFn(user32_module, BeginPaintFn, "BeginPaint"),
                .end_paint = try loadFn(user32_module, EndPaintFn, "EndPaint"),
                .get_client_rect = try loadFn(user32_module, GetClientRectFn, "GetClientRect"),
                .get_window_rect = try loadFn(user32_module, GetWindowRectFn, "GetWindowRect"),
                .get_dc = try loadFn(user32_module, GetDCFn, "GetDC"),
                .release_dc = try loadFn(user32_module, ReleaseDCFn, "ReleaseDC"),
                .fill_rect = try loadFn(user32_module, FillRectFn, "FillRect"),
                .draw_text_w = try loadFn(user32_module, DrawTextWFn, "DrawTextW"),
                .set_window_text_w = try loadFn(user32_module, SetWindowTextWFn, "SetWindowTextW"),
                .get_key_state = try loadFn(user32_module, GetKeyStateFn, "GetKeyState"),
                .set_window_pos = try loadFn(user32_module, SetWindowPosFn, "SetWindowPos"),
                .set_capture = try loadFn(user32_module, SetCaptureFn, "SetCapture"),
                .release_capture = try loadFn(user32_module, ReleaseCaptureFn, "ReleaseCapture"),
                .set_window_long_ptr_w = try loadFn(user32_module, SetWindowLongPtrWFn, "SetWindowLongPtrW"),
                .get_window_long_ptr_w = try loadFn(user32_module, GetWindowLongPtrWFn, "GetWindowLongPtrW"),
                .get_window_placement = try loadFn(user32_module, GetWindowPlacementFn, "GetWindowPlacement"),
                .set_window_placement = try loadFn(user32_module, SetWindowPlacementFn, "SetWindowPlacement"),
                .monitor_from_window = try loadFn(user32_module, MonitorFromWindowFn, "MonitorFromWindow"),
                .get_monitor_info_w = try loadFn(user32_module, GetMonitorInfoWFn, "GetMonitorInfoW"),
                .enum_display_monitors = try loadFn(user32_module, EnumDisplayMonitorsFn, "EnumDisplayMonitors"),
                .track_mouse_event = try loadFn(user32_module, TrackMouseEventFn, "TrackMouseEvent"),
                .get_system_metrics = try loadFn(user32_module, GetSystemMetricsFn, "GetSystemMetrics"),
                .create_menu = try loadFn(user32_module, CreateMenuFn, "CreateMenu"),
                .append_menu_w = try loadFn(user32_module, AppendMenuWFn, "AppendMenuW"),
                .set_menu = try loadFn(user32_module, SetMenuFn, "SetMenu"),
                .draw_menu_bar = try loadFn(user32_module, DrawMenuBarFn, "DrawMenuBar"),
                .post_message_w = try loadFn(user32_module, PostMessageWFn, "PostMessageW"),
                .destroy_menu = try loadFn(user32_module, DestroyMenuFn, "DestroyMenu"),
                .load_image_w = try loadFn(user32_module, LoadImageWFn, "LoadImageW"),
                .send_message_w = try loadFn(user32_module, SendMessageWFn, "SendMessageW"),
                .invalidate_rect = try loadFn(user32_module, InvalidateRectFn, "InvalidateRect"),
                .set_timer = try loadFn(user32_module, SetTimerFn, "SetTimer"),
                .kill_timer = try loadFn(user32_module, KillTimerFn, "KillTimer"),
            },
            .gdi32 = .{
                .create_solid_brush = try loadFn(gdi32_module, CreateSolidBrushFn, "CreateSolidBrush"),
                .delete_object = try loadFn(gdi32_module, DeleteObjectFn, "DeleteObject"),
                .set_text_color = try loadFn(gdi32_module, SetTextColorFn, "SetTextColor"),
                .set_bk_mode = try loadFn(gdi32_module, SetBkModeFn, "SetBkMode"),
                .select_object = try loadFn(gdi32_module, SelectObjectFn, "SelectObject"),
                .create_font_w = try loadFn(gdi32_module, CreateFontWFn, "CreateFontW"),
                .ext_text_out_w = try loadFn(gdi32_module, ExtTextOutWFn, "ExtTextOutW"),
                .text_out_w = try loadFn(gdi32_module, TextOutWFn, "TextOutW"),
                .create_compatible_dc = try loadFn(gdi32_module, CreateCompatibleDCFn, "CreateCompatibleDC"),
                .create_compatible_bitmap = try loadFn(gdi32_module, CreateCompatibleBitmapFn, "CreateCompatibleBitmap"),
                .delete_dc = try loadFn(gdi32_module, DeleteDCFn, "DeleteDC"),
                .bit_blt = try loadFn(gdi32_module, BitBltFn, "BitBlt"),
                .get_di_bits = try loadFn(gdi32_module, GetDIBitsFn, "GetDIBits"),
                .get_text_metrics_w = try loadFn(gdi32_module, GetTextMetricsWFn, "GetTextMetricsW"),
                .get_text_extent_point32_w = try loadFn(gdi32_module, GetTextExtentPoint32WFn, "GetTextExtentPoint32W"),
                .get_glyph_indices_w = try loadFn(gdi32_module, GetGlyphIndicesWFn, "GetGlyphIndicesW"),
            },
            .open_clipboard = try loadFn(user32_module, OpenClipboardFn, "OpenClipboard"),
            .close_clipboard = try loadFn(user32_module, CloseClipboardFn, "CloseClipboard"),
            .empty_clipboard = try loadFn(user32_module, EmptyClipboardFn, "EmptyClipboard"),
            .set_clipboard_data = try loadFn(user32_module, SetClipboardDataFn, "SetClipboardData"),
            .get_clipboard_data = try loadFn(user32_module, GetClipboardDataFn, "GetClipboardData"),
            .is_clipboard_format_available = try loadFn(user32_module, IsClipboardFormatAvailableFn, "IsClipboardFormatAvailable"),
            .global_alloc = try loadFn(kernel32_module, GlobalAllocFn, "GlobalAlloc"),
            .global_lock = try loadFn(kernel32_module, GlobalLockFn, "GlobalLock"),
            .global_unlock = try loadFn(kernel32_module, GlobalUnlockFn, "GlobalUnlock"),
            .global_free = try loadFn(kernel32_module, GlobalFreeFn, "GlobalFree"),
        };
    }
};

fn loadFn(module: HMODULE, comptime T: type, comptime name: [:0]const u8) !T {
    const symbol = windows.kernel32.GetProcAddress(module, name.ptr) orelse return error.MissingWin32Symbol;
    return @as(T, @ptrCast(symbol));
}

pub fn moduleHandle() !HINSTANCE {
    if (!supported) return error.UnsupportedPlatform;
    const module = windows.kernel32.GetModuleHandleW(null) orelse return error.GetModuleHandleFailed;
    return @ptrCast(module);
}

pub fn utf8ToWide(allocator: std.mem.Allocator, input: []const u8) ![]u16 {
    return try std.unicode.utf8ToUtf16LeAlloc(allocator, input);
}

pub fn utf8ToWideZ(allocator: std.mem.Allocator, input: []const u8) ![:0]u16 {
    return try std.unicode.utf8ToUtf16LeAllocZ(allocator, input);
}

pub extern "kernel32" fn GetDiskFreeSpaceExW(
    lpDirectoryName: LPCWSTR,
    lpFreeBytesAvailableToCaller: ?*u64,
    lpTotalNumberOfBytes: ?*u64,
    lpTotalNumberOfFreeBytes: ?*u64,
) callconv(.winapi) BOOL;

test "win32 type surface exists" {
    try std.testing.expect(@sizeOf(Rect) > 0);
}
