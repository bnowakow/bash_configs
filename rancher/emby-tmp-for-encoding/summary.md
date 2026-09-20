# Emby transcoding comparison summary

## Scope

Compared these runs:

- Proxmox3: local input → local output
- Proxmox3: NAS input → local output
- Proxmox3: NAS input → NAS output
- NAS host: NAS input → NAS output

The Proxmox runs contain 264 run folders each and 228 ffmpeg logs each. The NAS-host run contains 21 run folders and 21 ffmpeg logs.

Speeds below are median final ffmpeg `speed=` values, expressed as multiples of realtime. Higher is faster. Encoder labels identify the actual output encoder: `h264_qsv` and `h264_vaapi` are hardware encoders; `libx264` is software encoding.

## Fastest method per input and output parameters

| Input file | Input resolution | Input bitrate | Output parameters | Proxmox local→local | Proxmox NAS→local | Proxmox NAS→NAS | NAS host NAS→NAS |
|---|---:|---:|---|---:|---:|---:|---:|
| Tears of Steel | 1920×1080 | 1.795 MB/s | 960×540 | `h264_qsv` HW — **16.20×** | `h264_qsv` HW — **16.70×** | `h264_qsv` HW — **16.80×** | `libx264` SW — **17.10×** |
| LG Dolby Vision | 3840×2160 | 31.974 MB/s | Native | `h264_qsv` HW — **2.38×** | `h264_qsv` HW — **2.26×** | `h264_qsv` HW — **2.10×** | `libx264` SW — **1.48×** |
| Billy Lynn | 3840×2076 | 63.790 MB/s | 1920×1038 | `h264_vaapi` HW — **1.02×** | `h264_vaapi` HW — **1.04×** | `h264_vaapi` HW — **1.10×** | `libx264` SW — **0.83×** |
| Subtitle TS | 720×576 | 6.010 MB/s | 360×288 | `h264_vaapi` HW — **31.25×** | `h264_vaapi` HW — **35.15×** | `h264_vaapi` HW — **29.40×** | `libx264` SW — **35.30×** |
| Big Buck Bunny | 3840×2160 | 7.980 MB/s | 1920×1080 | `h264_qsv` HW — **4.00×** | `h264_qsv` HW — **4.43×** | `h264_qsv` HW — **4.36×** | `libx264` SW — **4.09×** |
| Tears of Steel | 1920×1080 | 1.795 MB/s | 426×240 | `h264_qsv` HW — **19.60×** | `h264_qsv` HW — **20.80×** | `h264_qsv` HW — **18.60×** | `libx264` SW — **21.60×** |
| Billy Lynn | 3840×2076 | 63.790 MB/s | 444×240 | `h264_vaapi` HW — **1.36×** | `h264_vaapi` HW — **1.42×** | `h264_vaapi` HW — **1.42×** | `libx264` SW — **1.64×** |
| Billy Lynn | 3840×2076 | 63.790 MB/s | Native | `h264_vaapi` HW — **0.57×** | `h264_vaapi` HW — **0.57×** | `h264_vaapi` HW — **0.60×** | `libx264` SW — **0.43×** |
| LG Dolby Vision | 3840×2160 | 31.974 MB/s | 1920×1080 | `h264_qsv` HW — **3.81×** | `h264_qsv` HW — **3.77×** | `h264_qsv` HW — **3.42×** | `libx264` SW — **2.58×** |
| Big Buck Bunny | 3840×2160 | 7.980 MB/s | Native | `h264_vaapi` HW — **2.32×** | `h264_qsv` HW — **2.42×** | `h264_qsv` HW — **2.46×** | `libx264` SW — **1.56×** |
| Big Buck Bunny | 3840×2160 | 7.980 MB/s | 426×240 | `h264_qsv` HW — **5.42×** | `h264_qsv` HW — **5.84×** | `h264_qsv` HW — **5.77×** | `libx264` SW — **8.79×** |
| Subtitle TS | 720×576 | 6.010 MB/s | 300×240 | `h264_vaapi` HW — **35.80×** | `h264_vaapi` HW — **32.70×** | `h264_vaapi` HW — **34.05×** | `libx264` SW — **37.50×** |
| Tears of Steel | 1920×1080 | 1.795 MB/s | Native | `h264_vaapi` HW — **10.29×** | `h264_qsv` HW — **10.40×** | `h264_qsv` HW — **9.96×** | `libx264` SW — **8.29×** |
| LG Dolby Vision | 3840×2160 | 31.974 MB/s | 426×240 | `h264_qsv` HW — **4.78×** | `h264_qsv` HW — **4.79×** | `h264_qsv` HW — **4.46×** | `libx264` SW — **3.15×** |
| Subtitle TS | 720×576 | 6.010 MB/s | Native | `h264_vaapi` HW — **27.00×** | `h264_vaapi` HW — **24.30×** | `h264_vaapi` HW — **23.25×** | `libx264` SW — **22.80×** |

The NAS host has only the software `libx264` encoder. Proxmox hardware QSV is generally fastest for heavier 1080p/4K workloads; VAAPI is often fastest for some subtitle and tone-mapping cases.

## Full-log validation

Every available ffmpeg log was checked for:

- an `Lsize` completion line;
- a muxing summary;
- an `out.mkv` output file;
- explicit ffmpeg failure markers.

Results:

- All 228 Proxmox ffmpeg logs have an `Lsize` line, muxing summary, and output file.
- All 21 NAS-host ffmpeg logs have an `Lsize` line, muxing summary, and output file.
- Proxmox runs 193–228 have no ffmpeg logs, although output files exist; they cannot be treated as clean ffmpeg passes.
- Proxmox runs 121–144 and 157–168 contain repeated `Error while decoding stream #0:0: Input/output error` messages in all three Proxmox layouts. They still produce output, but should be classified as errored/degraded, not clean passes.
- The NAS-host ffmpeg logs contain no decoding or conversion failure markers.

Therefore, there are no asymmetric clean pass/fail results in the 21-test overlap. The Proxmox host does have 48 tests with decoding I/O errors, common to all three Proxmox storage layouts. These errors appear host/input-side rather than caused by the selected read/write path.

Input bitrates are decimal MB/s conversions of the ffmpeg-reported container bitrate: 1 MB/s = 1,000 kb/s.
