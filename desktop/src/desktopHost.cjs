// Tiene il widget subito sopra il desktop e sotto tutte le altre finestre, come DesktopHost.cs di Pinboard.
// Quando "Mostra desktop" (Win+D) porta il desktop in primo piano, il widget diventa per un momento
// "sempre in primo piano" per restare visibile; quando torna attiva un'altra finestra, ridiventa normale.
// Le funzioni di user32.dll si chiamano con koffi; se non si carica, il widget resta una finestra normale.

const GWL_EXSTYLE = -20;
const WS_EX_TOOLWINDOW = 0x00000080;
const WS_EX_NOACTIVATE = 0x08000000;
const WS_EX_APPWINDOW = 0x00040000;

const SWP_NOSIZE = 0x0001;
const SWP_NOMOVE = 0x0002;
const SWP_NOACTIVATE = 0x0010;
const SWP_SHOWWINDOW = 0x0040;
const HWND_TOPMOST = -1;
const HWND_NOTOPMOST = -2;
const SW_SHOWNOACTIVATE = 4;

let user32 = null;
if (process.platform === 'win32') {
  try {
    const koffi = require('koffi');
    const lib = koffi.load('user32.dll');
    koffi.proto('int __stdcall EnumWindowsProc(intptr hwnd, intptr lParam)');
    user32 = {
      FindWindowW: lib.func('intptr __stdcall FindWindowW(str16 cls, str16 title)'),
      FindWindowExW: lib.func('intptr __stdcall FindWindowExW(intptr parent, intptr after, str16 cls, str16 title)'),
      EnumWindows: lib.func('int __stdcall EnumWindows(EnumWindowsProc *proc, intptr lParam)'),
      GetWindowLongW: lib.func('int32 __stdcall GetWindowLongW(intptr hwnd, int index)'),
      SetWindowLongW: lib.func('int32 __stdcall SetWindowLongW(intptr hwnd, int index, int32 value)'),
      SetWindowPos: lib.func('int __stdcall SetWindowPos(intptr hwnd, intptr after, int x, int y, int cx, int cy, uint32 flags)'),
      GetForegroundWindow: lib.func('intptr __stdcall GetForegroundWindow()'),
      GetClassNameW: lib.func('int __stdcall GetClassNameW(intptr hwnd, void *name, int max)'),
      IsWindowVisible: lib.func('int __stdcall IsWindowVisible(intptr hwnd)'),
      IsIconic: lib.func('int __stdcall IsIconic(intptr hwnd)'),
      ShowWindow: lib.func('int __stdcall ShowWindow(intptr hwnd, int cmd)'),
      RegisterWindowMessageW: lib.func('uint32 __stdcall RegisterWindowMessageW(str16 name)'),
    };
  } catch (error) {
    console.warn('ExamsTrack: widget senza aggancio al desktop (koffi non disponibile)', error);
    user32 = null;
  }
}

const isAvailable = () => user32 !== null;

/** HWND dal buffer di `BrowserWindow.getNativeWindowHandle()`. */
function handleOf(win) {
  const buffer = win.getNativeWindowHandle();
  return buffer.length >= 8 ? Number(buffer.readBigUInt64LE(0)) : buffer.readUInt32LE(0);
}

function classOf(hwnd) {
  const buffer = Buffer.alloc(512);
  const length = user32.GetClassNameW(hwnd, buffer, 256);
  return length > 0 ? buffer.toString('utf16le', 0, length * 2) : '';
}

/** Finestra di primo livello che contiene le icone del desktop (Progman o WorkerW). */
function findDesktopTopLevel() {
  const progman = user32.FindWindowW('Progman', null);
  if (user32.FindWindowExW(progman, 0, 'SHELLDLL_DefView', null) !== 0) return progman;
  let found = 0;
  user32.EnumWindows((top) => {
    if (user32.FindWindowExW(top, 0, 'SHELLDLL_DefView', null) !== 0) {
      found = top;
      return 0;
    }
    return 1;
  }, 0);
  return found || progman;
}

let desktopMode = false;

/** Mette la finestra subito sopra il desktop: fuori dalla barra delle applicazioni e da Alt+Tab, senza attivarsi. */
function placeAboveDesktop(win) {
  if (!user32 || win.isDestroyed()) return;
  const hwnd = handleOf(win);
  const ex = user32.GetWindowLongW(hwnd, GWL_EXSTYLE);
  user32.SetWindowLongW(hwnd, GWL_EXSTYLE, (ex | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE) & ~WS_EX_APPWINDOW);
  // Indicare come "hWndInsertAfter" una finestra non topmost toglie anche il flag topmost.
  user32.SetWindowPos(hwnd, findDesktopTopLevel(), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  desktopMode = false;
}

/**
 * Da chiamare a intervalli: quando il desktop passa in primo piano (Win+D) il widget diventa topmost;
 * quando torna attiva un'altra finestra, ridiventa normale subito sopra il desktop.
 */
function keepVisible(win) {
  if (!user32 || win.isDestroyed()) return;
  const hwnd = handleOf(win);
  const foreground = user32.GetForegroundWindow();
  const fgClass = foreground ? classOf(foreground) : '';
  const desktopFocused = fgClass === 'Progman' || fgClass === 'WorkerW';

  if (user32.IsIconic(hwnd) || !user32.IsWindowVisible(hwnd)) user32.ShowWindow(hwnd, SW_SHOWNOACTIVATE);

  const flags = SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE;
  if (desktopFocused && !desktopMode) {
    user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, flags);
    desktopMode = true;
  } else if (!desktopFocused && desktopMode) {
    user32.SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, flags);
    user32.SetWindowPos(hwnd, findDesktopTopLevel(), 0, 0, 0, 0, flags);
    desktopMode = false;
  }
}

/** Messaggio che Explorer invia quando si riavvia: il desktop cambia e il widget va rimesso al suo posto. */
function taskbarCreatedMessage() {
  return user32 ? user32.RegisterWindowMessageW('TaskbarCreated') : 0;
}

module.exports = { isAvailable, placeAboveDesktop, keepVisible, taskbarCreatedMessage };
