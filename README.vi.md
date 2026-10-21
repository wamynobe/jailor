<p align="center">
  <img src="docs/icon.png" width="96" height="96" alt="Jailor app icon">
</p>

<h1 align="center">Jailor</h1>

<p align="center"><strong>Workspace layout có nhãn, bền vững, cho macOS.</strong></p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Universal" src="https://img.shields.io/badge/arch-arm64%20%2B%20x86__64-blue">
  <img alt="Version 0.0.1" src="https://img.shields.io/badge/version-0.0.1-blue">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green">
</p>

<p align="center">
  Tiếng Việt · <a href="README.md">English</a>
</p>

Jailor gán cửa sổ thật của ứng dụng vào các khung có tên và có nhãn, rồi ghi nhớ các assignment đó. Đây không phải trình tự động chia cửa sổ hay desktop ảo: Jailor di chuyển, resize và focus cửa sổ thật thông qua Accessibility API của macOS.

> **Trạng thái: 0.0.1 (alpha).** Yêu cầu macOS 14+. Chưa có bản release đóng gói sẵn.

## Tính năng

- **Khung chỉnh được** — dùng preset hoặc tự di chuyển/resize khung.
- **Nhiều layout** — workspace riêng cho code, họp, nghiên cứu…
- **Nhãn** — phân loại cửa sổ, đặt nhãn ưu tiên cho từng khung.
- **Gán nhanh** — kéo thả, palette, hoặc phím tắt.
- **Hiện workspace** — ẩn giao diện Jailor, xếp layout và đưa các cửa sổ đã gán lên trước.
- **Dock / Cmd+Tab** — mở workspace thay vì mở một app trống.
- **Tự khôi phục** — xếp lại layout khi mở app; tuỳ chọn mở lại app đã đóng.
- **Lấp khung trống** — đưa các cửa sổ đang mở, chưa gán vào khung trống.
- **Universal binary** — chạy native trên Apple Silicon và Intel.
- **Lưu JSON local** — không tài khoản, không gửi dữ liệu lên mạng.

## Cài đặt

```bash
git clone https://github.com/wamynobe/jailor.git
cd jailor
make app
open build/Jailor.app
```

`make app` tạo `build/Jailor.app` universal, ký ad-hoc, cho cả arm64 và x86_64.

Build nhanh một kiến trúc:

```bash
JAILOR_ARCHS="arm64-apple-macosx14.0" ./scripts/build-app.sh
JAILOR_ARCHS="x86_64-apple-macosx14.0" ./scripts/build-app.sh
```

## Lần đầu mở app

1. Mở `build/Jailor.app`.
2. Cấp quyền **Accessibility** khi banner xuất hiện.
3. Quay lại Jailor, bấm **Kiểm tra lại**.
4. Nếu macOS yêu cầu thoát và mở lại app, làm theo.

Sau mỗi lần rebuild, chữ ký ad-hoc thay đổi; có thể cần cấp lại Accessibility.

## Sử dụng

1. Chọn hoặc tạo một layout.
2. Bấm **Chỉnh sửa** để chỉnh khung và chọn màn hình đích.
3. Gán cửa sổ:
   - kéo cửa sổ từ sidebar vào khung, hoặc
   - bấm `⌃⌥Space`, chọn nhãn, rồi bấm `1–9`, hoặc
   - bấm `⌃⌥1…9` để đưa cửa sổ đang focus vào khung.
4. Bấm **Áp dụng** hoặc `⌘↩`.
5. Để Dock/Cmd+Tab mở workspace, bật **Cài đặt → Giao diện → Chế độ workspace**.

## Phím tắt

### Global

| Phím | Tác dụng |
|---|---|
| `⌃⌥Space` | Mở palette gán nhanh |
| `⌃⌥1` … `⌃⌥9` | Gán cửa sổ đang focus vào khung 1…9 |
| `⌃⌥R` | Ẩn giao diện Jailor và hiện workspace |

### Local

| Phím | Tác dụng |
|---|---|
| `⌘↩` | Áp dụng layout đang chọn |
| `⌘⇧R` | Ẩn dashboard và hiện workspace |
| `⌘0` | Mở dashboard |

### Palette

`1–9` gán · `Tab` / `←` / `→` đổi nhãn · `Return` gán vào khung đang hover · `Esc` đóng.

## Cách hoạt động

- **Cửa sổ thật** — Accessibility di chuyển và resize cửa sổ của app khác.
- **Nhận diện ổn định** — assignment lưu CGWindowID; nếu không có, fallback theo tiêu đề/vị trí khung. Trường hợp mơ hồ sẽ báo “chưa tìm thấy” thay vì chọn nhầm cửa sổ.
- **Focus chính xác** — khi reveal, Jailor activate từng app và set đúng cửa sổ thành key window, tránh việc app nhiều cửa sổ hiện sai cửa sổ.
- **Hotkey chạy nền** — Carbon hotkey + global `NSEvent` monitor; tắt automatic termination/App Nap khi Jailor đang chạy.
- **State local** — layout, nhãn và assignment lưu tại `~/Library/Application Support/Jailor/state.json`.

## Giới hạn

- Bắt buộc có quyền Accessibility.
- Một số cửa sổ fullscreen, dialog hệ thống, hoặc app có giới hạn kích thước cứng không thể xếp chính xác.
- Không sandbox, không phù hợp Mac App Store; chỉ phân phối trực tiếp.
- Build ký ad-hoc; cần cấp lại Accessibility sau khi rebuild.
- Mỗi layout gắn với một màn hình. Cửa sổ ở Space khác có thể không hiện cùng lúc.
- Tên do bạn tạo (nhãn, khung, layout) không tự động dịch.

## Phát triển

```bash
make app      # build universal release
make test     # unit tests (10)
make icon     # tạo lại app icon
make clean
```

Cấu trúc chính:

```text
Sources/Jailor/       App, state, Accessibility, layout engine, views
Tests/JailorTests/    Hình học, tương thích, identity, localization
scripts/              Build và tạo icon
Resources/            Info.plist và AppIcon.icns
```

## Giấy phép

MIT. Xem [LICENSE](LICENSE).

## Ghi nhận

Lấy cảm hứng từ cộng đồng window manager: [Rectangle](https://github.com/rxhanson/Rectangle), [yabai](https://github.com/koekeishiya/yabai), [Amethyst](https://github.com/ianyh/Amethyst), [Hammerspoon](https://github.com/Hammerspoon/hammerspoon), [Loop](https://github.com/MrKai77/Loop), và [AltTab](https://github.com/lwouis/alt-tab-macos). Không liên kết với các dự án này.

---

Phiên bản **0.0.1** · Bundle ID `vn.quadbit.jailor`
