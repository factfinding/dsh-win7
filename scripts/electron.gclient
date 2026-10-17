# gclient config for the Electron v44.2.0 Win7 build; scripts\electron-sync.cmd copies it to e\.gclient.
# custom_deps drops Chromium's Chrome-updater test binaries: Windows Defender flags the
# chromium/third_party/updater/chrome_win_x86 CIPD package as unwanted software, which aborts
# `cipd ensure`; Electron does not build or test the updater.
solutions = [
  {
    "name": "src/electron",
    "url": "https://github.com/electron/electron",
    "deps_file": "DEPS",
    "managed": False,
    "custom_deps": {
      "src/third_party/updater/chrome_linux64/cipd": None,
      "src/third_party/updater/chrome_mac_universal/cipd": None,
      "src/third_party/updater/chrome_mac_universal_prod/cipd": None,
      "src/third_party/updater/chrome_win_arm64/cipd": None,
      "src/third_party/updater/chrome_win_x86/cipd": None,
      "src/third_party/updater/chrome_win_x86_64/cipd": None,
      "src/third_party/updater/chrome_linux64_sans_iid/cipd": None,
      "src/third_party/updater/chrome_mac_universal_sans_iid/cipd": None,
      "src/third_party/updater/chrome_mac_universal_prod_sans_iid/cipd": None,
      "src/third_party/updater/chrome_win_arm64_sans_iid/cipd": None,
      "src/third_party/updater/chrome_win_x86_sans_iid/cipd": None,
      "src/third_party/updater/chrome_win_x86_64_sans_iid/cipd": None,
      "src/third_party/updater/chromium_linux64/cipd": None,
      "src/third_party/updater/chromium_mac_amd64/cipd": None,
      "src/third_party/updater/chromium_mac_arm64/cipd": None,
      "src/third_party/updater/chromium_win_arm64/cipd": None,
      "src/third_party/updater/chromium_win_x86/cipd": None,
      "src/third_party/updater/chromium_win_x86_64/cipd": None,
      "src/third_party/updater/chromium_linux64_sans_iid/cipd": None,
      "src/third_party/updater/chromium_mac_amd64_sans_iid/cipd": None,
      "src/third_party/updater/chromium_mac_arm64_sans_iid/cipd": None,
      "src/third_party/updater/chromium_win_arm64_sans_iid/cipd": None,
      "src/third_party/updater/chromium_win_x86_sans_iid/cipd": None,
      "src/third_party/updater/chromium_win_x86_64_sans_iid/cipd": None,
    },
    "custom_vars": {},
  },
]
