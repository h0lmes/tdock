// Diagnostic tool only. Capture the verification window's encoded frame IDs.
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

template<class T> struct Com {
    T* value = nullptr;
    ~Com() { if (value) value->Release(); }
    T** put() { return &value; }
    T* operator->() const { return value; }
};

static void check(HRESULT status, const char* operation) {
    if (FAILED(status)) {
        std::cerr << operation << " failed: 0x" << std::hex
                  << static_cast<unsigned long>(status) << std::dec << '\n';
        throw std::runtime_error(operation);
    }
}

static void dpi_aware() {
    using SetContext = HANDLE (WINAPI*)(HANDLE);
    SetContext set = nullptr;
    auto address = GetProcAddress(GetModuleHandleW(L"user32.dll"), "SetThreadDpiAwarenessContext");
    static_assert(sizeof(set) == sizeof(address), "Windows function pointer size");
    std::memcpy(&set, &address, sizeof(set));
    if (set) set(reinterpret_cast<HANDLE>(-4));
    else SetProcessDPIAware();
}

static void inventory() {
    Com<IDXGIFactory1> factory;
    check(CreateDXGIFactory1(__uuidof(IDXGIFactory1),
        reinterpret_cast<void**>(factory.put())), "CreateDXGIFactory1");
    std::cout << "adapter,output,device,width,height,current_hz,supports_60,supports_120,adapter_name\n";
    for (UINT a = 0;; ++a) {
        Com<IDXGIAdapter1> adapter;
        if (factory->EnumAdapters1(a, adapter.put()) == DXGI_ERROR_NOT_FOUND) break;
        DXGI_ADAPTER_DESC1 adapter_desc{};
        check(adapter->GetDesc1(&adapter_desc), "GetDesc1");
        for (UINT o = 0;; ++o) {
            Com<IDXGIOutput> output;
            if (adapter->EnumOutputs(o, output.put()) == DXGI_ERROR_NOT_FOUND) break;
            DXGI_OUTPUT_DESC desc{};
            check(output->GetDesc(&desc), "GetDesc");
            if (!desc.AttachedToDesktop) continue;
            DEVMODEW mode{};
            mode.dmSize = sizeof(mode);
            if (!EnumDisplaySettingsW(desc.DeviceName, ENUM_CURRENT_SETTINGS, &mode)) continue;
            UINT count = 0;
            check(output->GetDisplayModeList(DXGI_FORMAT_B8G8R8A8_UNORM, 0,
                &count, nullptr), "GetDisplayModeList count");
            std::vector<DXGI_MODE_DESC> modes(count);
            check(output->GetDisplayModeList(DXGI_FORMAT_B8G8R8A8_UNORM, 0,
                &count, modes.data()), "GetDisplayModeList");
            bool sixty = false, one_twenty = false;
            for (const auto& m : modes) {
                if (m.Width != mode.dmPelsWidth || m.Height != mode.dmPelsHeight ||
                    !m.RefreshRate.Denominator) continue;
                const double hz = double(m.RefreshRate.Numerator) / m.RefreshRate.Denominator;
                sixty |= hz > 59 && hz < 61;
                one_twenty |= hz > 119 && hz < 121;
            }
            char device[64]{};
            char adapter_name[384]{};
            WideCharToMultiByte(CP_UTF8, 0, desc.DeviceName, -1,
                device, sizeof(device), nullptr, nullptr);
            WideCharToMultiByte(CP_UTF8, 0, adapter_desc.Description, -1,
                adapter_name, sizeof(adapter_name), nullptr, nullptr);
            std::cout << a << ',' << o << ',' << device << ','
                      << mode.dmPelsWidth << ',' << mode.dmPelsHeight << ','
                      << mode.dmDisplayFrequency << ',' << sixty << ',' << one_twenty
                      << ',' << adapter_name << '\n';
        }
    }
}

struct FindContext { DWORD pid; HWND window; };
static BOOL CALLBACK find_probe(HWND window, LPARAM parameter) {
    auto& context = *reinterpret_cast<FindContext*>(parameter);
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (pid != context.pid || !IsWindowVisible(window)) return TRUE;
    wchar_t title[96]{};
    GetWindowTextW(window, title, 96);
    if (std::wstring(title) != L"TDock animation verification") return TRUE;
    context.window = window;
    return FALSE;
}

struct Sample {
    unsigned sequence;
    long long presented, captured;
    unsigned accumulated;
};

// Opaque GDI control: no tdock renderer, GDI+, layered window, or icon worker.
static LRESULT CALLBACK control_window(HWND window, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_NCHITTEST) return HTTRANSPARENT;
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_PAINT) {
        PAINTSTRUCT paint{};
        BeginPaint(window, &paint);
        EndPaint(window, &paint);
        return 0;
    }
    return DefWindowProcW(window, message, w, l);
}
static void control(unsigned hz, const char* ready_path, const char* destination) {
    if (hz != 60 && hz != 120) throw std::runtime_error("Control rate must be 60 or 120 Hz");
    RECT work{};
    if (!SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0))
        throw std::runtime_error("Cannot read the work area");
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = control_window;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.lpszClassName = L"TDockNativeGdiControl";
    RegisterClassW(&window_class);
    HWND window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        window_class.lpszClassName, L"TDock animation verification", WS_POPUP,
        work.left + 80, work.top + 80, 128, 128, nullptr, nullptr,
        GetModuleHandleW(nullptr), nullptr);
    if (!window) throw std::runtime_error("Cannot create the GDI control");
    struct Destroy { HWND window; ~Destroy() { DestroyWindow(window); } } destroy{window};
    SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    UpdateWindow(window);
    const auto deadline = GetTickCount64() + 15000;
    while (GetFileAttributesA(ready_path) == INVALID_FILE_ATTRIBUTES) {
        if (GetTickCount64() >= deadline) throw std::runtime_error("Control handshake timed out");
        Sleep(10);
    }
    MONITORINFOEXW monitor{};
    monitor.cbSize = sizeof(monitor);
    GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor);
    DEVMODEW mode{};
    mode.dmSize = sizeof(mode);
    EnumDisplaySettingsW(monitor.szDevice, ENUM_CURRENT_SETTINGS, &mode);
    LARGE_INTEGER frequency{}, start{};
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&start);
    HANDLE timer = CreateWaitableTimerExW(nullptr, nullptr, 2, TIMER_ALL_ACCESS);
    if (!timer) timer = CreateWaitableTimerW(nullptr, FALSE, nullptr);
    if (!timer) throw std::runtime_error("Cannot create the control timer");
    struct Close { HANDLE value; ~Close() { CloseHandle(value); } } close{timer};
    std::ofstream csv(destination);
    csv << "sequence,sample_qpc,submit_qpc,requested_hz,effective_hz,display_hz,clock_source\n";
    HBRUSH black = CreateSolidBrush(RGB(0, 0, 0));
    HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
    HBRUSH green = CreateSolidBrush(RGB(0, 255, 0));
    for (unsigned sequence = 1; sequence <= 240; ++sequence) {
        LARGE_INTEGER now{};
        QueryPerformanceCounter(&now);
        const double remaining = double(start.QuadPart) +
            double(sequence) * frequency.QuadPart / hz - now.QuadPart;
        if (remaining > 0) {
            LARGE_INTEGER due{};
            due.QuadPart = -std::max(1LL, static_cast<long long>(remaining * 10000000 / frequency.QuadPart));
            SetWaitableTimer(timer, &due, 0, nullptr, nullptr, FALSE);
            WaitForSingleObject(timer, 1000);
        }
        MSG message{};
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        QueryPerformanceCounter(&now);
        HDC dc = GetDC(window);
        RECT base{0, 0, 128, 128}, guard{0, 0, 4, 4};
        FillRect(dc, &base, black);
        FillRect(dc, &guard, green);
        for (unsigned bit = 0; bit < 24; ++bit) {
            RECT cell{LONG(4 + bit * 4), 4, LONG(8 + bit * 4), 12};
            FillRect(dc, &cell, sequence & (1u << bit) ? white : black);
        }
        GdiFlush();
        ReleaseDC(window, dc);
        LARGE_INTEGER submitted{};
        QueryPerformanceCounter(&submitted);
        csv << sequence << ',' << now.QuadPart << ',' << submitted.QuadPart << ','
            << hz << ',' << hz << ',' << mode.dmDisplayFrequency << ",native_gdi_control\n";
    }
    DeleteObject(black);
    DeleteObject(white);
    DeleteObject(green);
    Sleep(250);
    std::cout << "submitted_frames=240,native_gdi_control=1\n";
}

static void capture(DWORD pid, const char* destination, const char* ready_path) {
    FindContext target{pid, nullptr};
    const ULONGLONG deadline = GetTickCount64() + 15000;
    do {
        EnumWindows(find_probe, reinterpret_cast<LPARAM>(&target));
        if (target.window) break;
        Sleep(10);
    } while (GetTickCount64() < deadline);
    if (!target.window) throw std::runtime_error("Verification window was not found");
    const HMONITOR monitor = MonitorFromWindow(target.window, MONITOR_DEFAULTTONEAREST);

    Com<IDXGIFactory1> factory;
    check(CreateDXGIFactory1(__uuidof(IDXGIFactory1),
        reinterpret_cast<void**>(factory.put())), "CreateDXGIFactory1");
    Com<IDXGIAdapter1> selected_adapter;
    Com<IDXGIOutput1> selected_output;
    DXGI_OUTPUT_DESC output_desc{};
    for (UINT a = 0; !selected_output.value; ++a) {
        Com<IDXGIAdapter1> adapter;
        if (factory->EnumAdapters1(a, adapter.put()) == DXGI_ERROR_NOT_FOUND) break;
        for (UINT o = 0;; ++o) {
            Com<IDXGIOutput> output;
            if (adapter->EnumOutputs(o, output.put()) == DXGI_ERROR_NOT_FOUND) break;
            DXGI_OUTPUT_DESC desc{};
            check(output->GetDesc(&desc), "GetDesc");
            if (desc.Monitor != monitor) continue;
            check(output->QueryInterface(__uuidof(IDXGIOutput1),
                reinterpret_cast<void**>(selected_output.put())), "IDXGIOutput1");
            selected_adapter.value = adapter.value;
            selected_adapter.value->AddRef();
            output_desc = desc;
            break;
        }
    }
    if (!selected_output.value) throw std::runtime_error("Target monitor was not found");
    Com<ID3D11Device> device;
    Com<ID3D11DeviceContext> context;
    D3D_FEATURE_LEVEL level{};
    check(D3D11CreateDevice(selected_adapter.value, D3D_DRIVER_TYPE_UNKNOWN,
        nullptr, 0, nullptr, 0, D3D11_SDK_VERSION, device.put(), &level,
        context.put()), "D3D11CreateDevice");
    Com<IDXGIOutputDuplication> duplication;
    check(selected_output->DuplicateOutput(device.value, duplication.put()), "DuplicateOutput");
    D3D11_TEXTURE2D_DESC staging_desc{};
    staging_desc.Width = 104;
    staging_desc.Height = 16;
    staging_desc.MipLevels = 1;
    staging_desc.ArraySize = 1;
    staging_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    staging_desc.SampleDesc.Count = 1;
    staging_desc.Usage = D3D11_USAGE_STAGING;
    staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    Com<ID3D11Texture2D> staging;
    check(device->CreateTexture2D(&staging_desc, nullptr, staging.put()), "CreateTexture2D");
    std::ofstream(ready_path) << "ready\n";
    std::vector<Sample> samples;
    unsigned previous = 0, invalid_markers = 0;
    const ULONGLONG capture_deadline = GetTickCount64() + 15000;
    while (IsWindow(target.window) && GetTickCount64() < capture_deadline) {
        DXGI_OUTDUPL_FRAME_INFO info{};
        Com<IDXGIResource> resource;
        HRESULT status = duplication->AcquireNextFrame(50, &info, resource.put());
        if (status == DXGI_ERROR_WAIT_TIMEOUT) continue;
        check(status, "AcquireNextFrame");
        try {
            if (info.LastPresentTime.QuadPart) {
                RECT rect{};
                if (!GetWindowRect(target.window, &rect)) {
                    duplication->ReleaseFrame();
                    break;
                }
                const int x = rect.left - output_desc.DesktopCoordinates.left;
                const int y = rect.top - output_desc.DesktopCoordinates.top;
                const int width = output_desc.DesktopCoordinates.right - output_desc.DesktopCoordinates.left;
                const int height = output_desc.DesktopCoordinates.bottom - output_desc.DesktopCoordinates.top;
                if (x >= 0 && y >= 0 && x + 104 <= width && y + 16 <= height) {
                    Com<ID3D11Texture2D> desktop;
                    check(resource->QueryInterface(__uuidof(ID3D11Texture2D),
                        reinterpret_cast<void**>(desktop.put())), "Desktop texture");
                    D3D11_BOX box{UINT(x), UINT(y), 0, UINT(x + 104), UINT(y + 16), 1};
                    context->CopySubresourceRegion(staging.value, 0, 0, 0, 0, desktop.value, 0, &box);
                    D3D11_MAPPED_SUBRESOURCE mapped{};
                    check(context->Map(staging.value, 0, D3D11_MAP_READ, 0, &mapped), "Map");
                    auto bytes = static_cast<const unsigned char*>(mapped.pData);
                    const auto guard = bytes + 2 * mapped.RowPitch + 2 * 4;
                    const bool valid = guard[1] > 180 && guard[2] < 80 && guard[0] < 100;
                    unsigned sequence = 0;
                    if (valid) {
                        for (unsigned bit = 0; bit < 24; ++bit) {
                            const auto pixel = bytes + 6 * mapped.RowPitch + (6 + bit * 4) * 4;
                            if (pixel[2] > 128) sequence |= 1u << bit;
                        }
                    } else ++invalid_markers;
                    context->Unmap(staging.value, 0);
                    if (valid && sequence && sequence != previous) {
                        LARGE_INTEGER now{};
                        QueryPerformanceCounter(&now);
                        samples.push_back({sequence, info.LastPresentTime.QuadPart,
                            now.QuadPart, info.AccumulatedFrames});
                        previous = sequence;
                    }
                }
            }
        } catch (...) {
            duplication->ReleaseFrame();
            throw;
        }
        check(duplication->ReleaseFrame(), "ReleaseFrame");
    }
    std::ofstream csv(destination);
    csv << "sequence,present_qpc,capture_qpc,accumulated_frames\n";
    for (const auto& sample : samples)
        csv << sample.sequence << ',' << sample.presented << ',' << sample.captured
            << ',' << sample.accumulated << '\n';
    if (samples.size() < 10) throw std::runtime_error("Too few verified desktop frames");
    std::cout << "captured_frames=" << samples.size()
              << ",first_sequence=" << samples.front().sequence
              << ",last_sequence=" << samples.back().sequence
              << ",invalid_markers=" << invalid_markers << '\n';
}

int main(int argc, char** argv) {
    try {
        dpi_aware();
        if (argc == 2 && std::string(argv[1]) == "inventory") inventory();
        else if (argc == 5 && std::string(argv[1]) == "capture")
            capture(static_cast<DWORD>(std::stoul(argv[2])), argv[3], argv[4]);
        else if (argc == 5 && std::string(argv[1]) == "control")
            control(std::stoul(argv[2]), argv[3], argv[4]);
        else throw std::runtime_error("Use inventory, capture PID CSV READY_FILE, or control HZ READY_FILE CSV");
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
