%module cpyHook
%include typemaps.i
%{
  #define _WIN32_WINNT 0x400
  #include "windows.h"

  #if PY_MAJOR_VERSION >= 3
    #define PY3K
  #endif

  PyObject* callback_funcs[WH_MAX];
  HHOOK hHooks[WH_MAX];
  BYTE key_state[256];
%}

#ifdef SWIGPYTHON
%typemap(in) PyObject *pyfunc {
  if (!PyCallable_Check($input)) {
    PyErr_SetString(PyExc_TypeError, "Need a callable object");
    return NULL;
  }
  $1 = $input;
}
#endif

%init %{
  memset(key_state, 0, 256);
  memset(callback_funcs, 0, WH_MAX);
  memset(hHooks, 0, WH_MAX);
  PyEval_InitThreads();
  
  // get initial key state
  Py_BEGIN_ALLOW_THREADS
	key_state[VK_NUMLOCK] = (GetKeyState(VK_NUMLOCK)&0x0001) ? 0x01 : 0x00;
	key_state[VK_CAPITAL] = (GetKeyState(VK_CAPITAL)&0x0001) ? 0x01 : 0x00;
	key_state[VK_SCROLL] = (GetKeyState(VK_SCROLL)&0x0001) ? 0x01 : 0x00;
	Py_END_ALLOW_THREADS
%}

%wrapper %{
  unsigned short ConvertToASCII(unsigned int keycode, unsigned int scancode);
	void UpdateKeyState(unsigned int vkey, WPARAM msg);

  LRESULT CALLBACK cLLKeyboardCallback(int code, WPARAM wParam, LPARAM lParam) {
    PyObject *arglist, *r;
    PKBDLLHOOKSTRUCT kbd;
    HWND hwnd;
    LPWSTR win_name = NULL;
    unsigned short ascii = 0;
    static int win_len;
    static LRESULT result;
    long pass = 1;
    PyGILState_STATE gil;

#ifndef PY3K
    int s_win_name_size;
    PSTR s_win_name = NULL;
#endif

    // uncomment this next bit if you do not want to process events like "ctl-alt-del"
    // and other events that are not supposed to be processed
    // as per msdn documentation:
    // http://msdn.microsoft.com/en-us/library/ms644985(VS.85).aspx

    // if message code < 0, return immediately
    //if(code<0)
    //    CallNextHookEx(hHooks[WH_KEYBOARD_LL], code, wParam, lParam);

    // get the GIL
    gil = PyGILState_Ensure();

    // cast to a keyboard event struct
    kbd = (PKBDLLHOOKSTRUCT)lParam;
    // get the current foreground window (might not be the real window that received the event)
    hwnd = GetForegroundWindow();

    // grab the window unicode name if possible
    win_len = GetWindowTextLengthW(hwnd);
    if(win_len > 0) {
	  win_name = (LPWSTR) malloc(sizeof(wchar_t) * win_len + 1);
	  GetWindowTextW(hwnd, win_name, win_len + 1);

#ifndef PY3K
      //UTF-8 encode the window name
      s_win_name_size = WideCharToMultiByte(CP_UTF8, 0, win_name, -1, NULL, 0, NULL, NULL);
      s_win_name = (PSTR) malloc(s_win_name_size);
      WideCharToMultiByte(CP_UTF8, 0, win_name, -1, s_win_name, s_win_name_size, NULL, NULL);
#endif
    }
    // convert to an ASCII code if possible
    ascii = ConvertToASCII(kbd->vkCode, kbd->scanCode);

    // pass the message on to the Python function
#ifdef PY3K
    arglist = Py_BuildValue("(iiiiiiiu)", wParam, kbd->vkCode, kbd->scanCode, ascii,
                            kbd->flags, kbd->time, hwnd, win_name);
#else
    arglist = Py_BuildValue("(iiiiiiis)", wParam, kbd->vkCode, kbd->scanCode, ascii,
                            kbd->flags, kbd->time, hwnd, s_win_name);
#endif
    if(arglist == NULL)
      PyErr_Print();

    r = PyObject_CallObject(callback_funcs[WH_KEYBOARD_LL], arglist);

    // check if we should pass the event on or not
    if(r == NULL)
      PyErr_Print();
    else
      pass = PyInt_AsLong(r);

    Py_XDECREF(r);
    Py_DECREF(arglist);
    // release the GIL
    PyGILState_Release(gil);

    // free the memory for the window name
    if(win_name != NULL){
      free(win_name);
#ifndef PY3K
      free(s_win_name);
#endif
    }

    // decide whether or not to call the next hook
    if(code < 0 || pass) {
			UpdateKeyState(kbd->vkCode, wParam);
      result = CallNextHookEx(hHooks[WH_KEYBOARD_LL], code, wParam, lParam);
    } else {
    	// return a non-zero to prevent further processing
      result = 42;
		}
    return result;
  }

  LRESULT CALLBACK cLLMouseCallback(int code, WPARAM wParam, LPARAM lParam) {
    PyObject *arglist, *r;
    PMSLLHOOKSTRUCT ms;
    HWND hwnd;
    LPWSTR win_name = NULL;
    static int win_len;
    static LRESULT result;
    long pass = 1;
    PyGILState_STATE gil;

#ifndef PY3K
    int s_win_name_size;
    PSTR s_win_name = NULL;
#endif

    // get the GIL
    gil = PyGILState_Ensure();

    //pass the message on to the Python function
    ms = (PMSLLHOOKSTRUCT)lParam;
    hwnd = WindowFromPoint(ms->pt);

    //grab the window unicode name if possible
    win_len = GetWindowTextLengthW(hwnd);
    if(win_len > 0) {
	  win_name = (LPWSTR) malloc(sizeof(wchar_t) * win_len + 1);
	  GetWindowTextW(hwnd, win_name, win_len + 1);

#ifndef PY3K
      //UTF-8 encode the window name
      s_win_name_size = WideCharToMultiByte(CP_UTF8, 0, win_name, -1, NULL, 0, NULL, NULL);
      s_win_name = (PSTR) malloc(s_win_name_size);
      WideCharToMultiByte(CP_UTF8, 0, win_name, -1, s_win_name, s_win_name_size, NULL, NULL);
#endif
    }
    //build the argument list to the callback function
#ifdef PY3K
    arglist = Py_BuildValue("(iiiiiiiu)", wParam, ms->pt.x, ms->pt.y, ms->mouseData,
                            ms->flags, ms->time, hwnd, win_name);
#else
    arglist = Py_BuildValue("(iiiiiiis)", wParam, ms->pt.x, ms->pt.y, ms->mouseData,
                            ms->flags, ms->time, hwnd, s_win_name);
#endif
    if(arglist == NULL)
      PyErr_Print();

    r = PyObject_CallObject(callback_funcs[WH_MOUSE_LL], arglist);

    // check if we should pass the event on or not
    if(r == NULL)
      PyErr_Print();
    else
      pass = PyInt_AsLong(r);

    Py_XDECREF(r);
    Py_DECREF(arglist);
    // release the GIL
    PyGILState_Release(gil);

    //free the memory for the window name
    if(win_name != NULL){
      free(win_name);
#ifndef PY3K
      free(s_win_name);
#endif
    }

    // decide whether or not to call the next hook
    if(code < 0 || pass)
      result = CallNextHookEx(hHooks[WH_MOUSE_LL], code, wParam, lParam);
    else {
    	// return non-zero to prevent further processing
      result = 42;
    }
    return result;
  }

  int cSetHook(int idHook, PyObject *pyfunc) {
    HINSTANCE hMod;

    //make sure we have a valid hook number
    if(idHook > WH_MAX || idHook < WH_MIN) {
      PyErr_SetString(PyExc_ValueError, "Hooking error: invalid hook ID");
    }

    //get the module handle
    Py_BEGIN_ALLOW_THREADS
    // try to get handle for current file - will succeed if called from a compiled .exe
    hMod = GetModuleHandle(NULL);
    if(NULL == hMod)    // otherwise use name for DLL
        hMod = GetModuleHandle("_cpyHook.pyd");
    Py_END_ALLOW_THREADS

    //switch on the type of hook so we point to the right C callback
    switch(idHook) {
      case WH_MOUSE_LL:
        if(callback_funcs[idHook] != NULL)
          break;

        callback_funcs[idHook] = pyfunc;
        Py_INCREF(callback_funcs[idHook]);

        Py_BEGIN_ALLOW_THREADS
        hHooks[idHook] = SetWindowsHookEx(WH_MOUSE_LL, cLLMouseCallback, (HINSTANCE) hMod, 0);
        Py_END_ALLOW_THREADS
        break;

      case WH_KEYBOARD_LL:
        if(callback_funcs[idHook] != NULL)
          break;

        callback_funcs[idHook] = pyfunc;
        Py_INCREF(callback_funcs[idHook]);

        Py_BEGIN_ALLOW_THREADS
        hHooks[idHook] = SetWindowsHookEx(WH_KEYBOARD_LL, cLLKeyboardCallback, (HINSTANCE) hMod, 0);
        Py_END_ALLOW_THREADS
        break;

      default:
       return 0;
    }

    if(!hHooks[idHook]) {
      PyErr_SetString(PyExc_TypeError, "Could not set hook");
    }

    return 1;
  }

  int cUnhook(int idHook) {
    BOOL result;

    //make sure we have a valid hook number
    if(idHook > WH_MAX || idHook < WH_MIN) {
      PyErr_SetString(PyExc_ValueError, "Invalid hook ID");
    }

    //unhook the callback
    Py_BEGIN_ALLOW_THREADS
    result = UnhookWindowsHookEx(hHooks[idHook]);
    Py_END_ALLOW_THREADS

    if(result) {
      //decrease the ref to the Python callback
    	Py_DECREF(callback_funcs[idHook]);
      callback_funcs[idHook] = NULL;
    }

    return result;
  }
  
  void SetKeyState(unsigned int vkey, int down) {
	  // (1 > 0) ? True : False
 		if (vkey == VK_MENU || vkey == VK_LMENU || vkey == VK_RMENU) {
 			key_state[vkey] = (down) ? 0x80 : 0x00;
// 			For some reason when doing ascii conversion if VK_MENU is set to 0x80
//          the ALT + NUM combination fails to write the character.
//          Also, in my spanish keyboard the combination alt gr + 4 stops working, it should
//          give me a '~', but sometimes worked if i spammed both keys repeatedly, very wierd...
//          I can write the 'á','é','í','ó','ú','à','è','ì','ò','ù' and others with ^ without problems. I also tried,
//          canadian french layout and it worked fine. The tests where made using a notepad.
//          I couldn't replicate the double deadkey bug for '¨', or '^' in the french layout because
//          my normal keyboard behavior is to write them twice.
//          According to MSDN a WM_SYSCOMMAND is generated when the F10 key or the
//          ALT + 'key' is pressed. I believe those key combinations should send an WM_SYSCOMMAND and when you do
//          the ascii conversion you break the syscommand and that stops the character being
//          written. Effectively, during tests both ALT and ALT GR generated a WM_SYSKEYUP and WM_SYSKEYDOWN events(these are
//          generated previous to WM_SYSCOMMAND).
//          Maybe i am breaking something else :P
// 			key_state[VK_MENU] = key_state[VK_LMENU] | key_state[VK_RMENU];
 		} else if (vkey == VK_SHIFT || vkey == VK_LSHIFT || vkey == VK_RSHIFT) {
 			key_state[vkey] = (down) ? 0x80 : 0x00;
 			key_state[VK_SHIFT] = key_state[VK_LSHIFT] | key_state[VK_RSHIFT];
 		} else if (vkey == VK_CONTROL || vkey == VK_LCONTROL || vkey == VK_RCONTROL) {
 			key_state[vkey] = (down) ? 0x80 : 0x00;
 			key_state[VK_CONTROL] = key_state[VK_LCONTROL] | key_state[VK_RCONTROL];
 		} else if (vkey == VK_NUMLOCK && !down) {
 			key_state[VK_NUMLOCK] = !key_state[VK_NUMLOCK];
 		} else if (vkey == VK_CAPITAL && !down) {
 			key_state[VK_CAPITAL] = !key_state[VK_CAPITAL];
 		} else if (vkey == VK_SCROLL && !down) {
 			key_state[VK_SCROLL] = !key_state[VK_SCROLL];
 		}
  }
  
  void UpdateKeyState(unsigned int vkey, WPARAM msg) {
  //TODO: Investigate if the press alt key bug crashes on x64
  	if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN) {
			SetKeyState(vkey, 1);
  	} else if (msg == WM_KEYUP || msg == WM_SYSKEYUP) {
			SetKeyState(vkey, 0);
  	}
  }
  
  unsigned int cGetKeyState(unsigned int vkey) {
  	return key_state[vkey];
  }

  unsigned short ConvertToASCII(unsigned int keycode, unsigned int scancode) {
    int r;
    unsigned short c = 0;

    Py_BEGIN_ALLOW_THREADS
    r = ToAscii(keycode, scancode, key_state, &c, 0);
    Py_END_ALLOW_THREADS
    if(r < 0) {
      //PyErr_SetString(PyExc_ValueError, "Could not convert to ASCII");
      return 0;
    }
    return c;
  }
%}

unsigned int cGetKeyState(unsigned int vkey);
int cSetHook(int idHook, PyObject *pyfunc);
int cUnhook(int idHook);
