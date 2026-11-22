<#
  make-art.ps1 - builds the addon's textures from art/logo-source.webp.

  Outputs
    Media/Logo.tga      256x256 full emblem, white background removed (circular alpha)
    Media/Icon.tga      64x64 icon (head crop inside a ring by default, or the full emblem with -IconStyle Full)
    docs/logo.png       512x512 full emblem for the README / CurseForge avatar
    art/preview/*.png   enlarged previews for checking by eye (not shipped)

  Uses only Windows' built-in imaging (WIC/WPF) plus a tiny TGA writer, so nothing needs installing.
  TGA is written as 32-bit uncompressed, bottom-left origin, power-of-two sizes (what WoW expects).
#>
param(
  [string]$Source = (Join-Path $PSScriptRoot '..\art\logo-source.webp'),
  [ValidateSet('Head', 'Full', 'Vector')][string]$IconStyle = 'Head',
  # Head crop, in units of the emblem radius, relative to the emblem centre.
  [double]$HeadX = 0.065,
  [double]$HeadY = -0.26,
  [double]$HeadSide = 0.29,
  # Optional small-size icon artwork (e.g. a vector render) used when -IconStyle Vector, and in -Compare sheets.
  [string]$VectorIcon = '',
  # Only write art/preview/* (never touches Media/ or docs/).
  [switch]$PreviewOnly,
  # Also write art/preview/compare.png: painted head crop vs. vector icon at 64 px and 24 px.
  [switch]$Compare
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase

if (-not ('SltArt' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
public static class SltArt {
  // Pixels are BGRA, top-down rows, 4 bytes per pixel.
  public static int[] BBox(byte[] p, int w, int h, int thresh) {
    int x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int i = (y * w + x) * 4;
        int mn = Math.Min(p[i + 2], Math.Min(p[i + 1], p[i]));
        if (mn < thresh) {
          if (x < x0) x0 = x; if (x > x1) x1 = x;
          if (y < y0) y0 = y; if (y > y1) y1 = y;
        }
      }
    }
    return new int[] { x0, y0, x1, y1 };
  }

  static double Clamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

  // Multiplies alpha by an anti-aliased disc of radius r centred on (cx, cy).
  public static void CircleMask(byte[] p, int w, int h, double cx, double cy, double r, double feather) {
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        double d = Math.Sqrt(dx * dx + dy * dy);
        double a = Clamp01((r - d) / feather + 0.5);
        int i = (y * w + x) * 4;
        // Premultiplied-safe: scale colour and alpha together.
        p[i] = (byte)Math.Round(p[i] * a);
        p[i + 1] = (byte)Math.Round(p[i + 1] * a);
        p[i + 2] = (byte)Math.Round(p[i + 2] * a);
        p[i + 3] = (byte)Math.Round(p[i + 3] * a);
      }
    }
  }

  // Draws an anti-aliased ring (band between rOuter - thick and rOuter) over the image ("over" blending, premultiplied).
  public static void Ring(byte[] p, int w, int h, double cx, double cy, double rOuter, double thick, byte r, byte g, byte b) {
    double rInner = rOuter - thick;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        double d = Math.Sqrt(dx * dx + dy * dy);
        double cov = Clamp01(Math.Min(rOuter - d, d - rInner) + 0.5);
        if (cov <= 0) continue;
        int i = (y * w + x) * 4;
        p[i] = (byte)Math.Round(b * cov + p[i] * (1 - cov));
        p[i + 1] = (byte)Math.Round(g * cov + p[i + 1] * (1 - cov));
        p[i + 2] = (byte)Math.Round(r * cov + p[i + 2] * (1 - cov));
        p[i + 3] = (byte)Math.Round(255 * cov + p[i + 3] * (1 - cov));
      }
    }
  }

  // Converts premultiplied BGRA to straight alpha (TGA/PNG consumers expect straight alpha).
  public static void Unpremultiply(byte[] p) {
    for (int i = 0; i < p.Length; i += 4) {
      int a = p[i + 3];
      if (a == 0) { p[i] = 0; p[i + 1] = 0; p[i + 2] = 0; continue; }
      if (a == 255) continue;
      p[i] = (byte)Math.Min(255, (p[i] * 255 + a / 2) / a);
      p[i + 1] = (byte)Math.Min(255, (p[i + 1] * 255 + a / 2) / a);
      p[i + 2] = (byte)Math.Min(255, (p[i + 2] * 255 + a / 2) / a);
    }
  }

  // 32-bit uncompressed true-colour TGA, bottom-left origin, 8 alpha bits.
  public static byte[] ToTga(byte[] p, int w, int h) {
    byte[] o = new byte[18 + w * h * 4];
    o[2] = 2;
    o[12] = (byte)(w & 255); o[13] = (byte)(w >> 8);
    o[14] = (byte)(h & 255); o[15] = (byte)(h >> 8);
    o[16] = 32; o[17] = 8;
    int k = 18;
    for (int y = h - 1; y >= 0; y--) {
      for (int x = 0; x < w; x++) {
        int i = (y * w + x) * 4;
        o[k++] = p[i]; o[k++] = p[i + 1]; o[k++] = p[i + 2]; o[k++] = p[i + 3];
      }
    }
    return o;
  }
}
'@
}

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$mediaDir = Join-Path $root 'Media'
$docsDir = Join-Path $root 'docs'
$previewDir = Join-Path $root 'art\preview'
foreach ($d in $mediaDir, $docsDir, $previewDir) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

# --- load source -----------------------------------------------------------------------------------
$fs = [IO.File]::OpenRead((Resolve-Path $Source))
try {
  $dec = [Windows.Media.Imaging.BitmapDecoder]::Create($fs, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
  $src = New-Object Windows.Media.Imaging.FormatConvertedBitmap($dec.Frames[0], [Windows.Media.PixelFormats]::Bgra32, $null, 0)
  $src.Freeze()
} finally { $fs.Close() }
$W = $src.PixelWidth; $H = $src.PixelHeight
$px = New-Object byte[] ($W * $H * 4)
$src.CopyPixels($px, $W * 4, 0)

# --- find the emblem (everything that isn't near-white) ----------------------------------------------
$bb = [SltArt]::BBox($px, $W, $H, 225)
$cx = ($bb[0] + $bb[2] + 1) / 2.0
$cy = ($bb[1] + $bb[3] + 1) / 2.0
$r = [Math]::Max($bb[2] - $bb[0] + 1, $bb[3] - $bb[1] + 1) / 2.0
"Source {0}x{1}; emblem centre ({2:N1}, {3:N1}), radius {4:N1}" -f $W, $H, $cx, $cy, $r

function Get-Scaled([int]$x, [int]$y, [int]$side, [int]$size) {
  $x = [Math]::Max(0, [Math]::Min($x, $script:W - $side)); $y = [Math]::Max(0, [Math]::Min($y, $script:H - $side))
  $crop = New-Object Windows.Media.Imaging.CroppedBitmap($src, (New-Object Windows.Int32Rect($x, $y, $side, $side)))
  $dv = New-Object Windows.Media.DrawingVisual
  [Windows.Media.RenderOptions]::SetBitmapScalingMode($dv, [Windows.Media.BitmapScalingMode]::HighQuality)
  $dc = $dv.RenderOpen()
  $dc.DrawImage($crop, (New-Object Windows.Rect(0, 0, $size, $size)))
  $dc.Close()
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($size, $size, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($dv)
  $bytes = New-Object byte[] ($size * $size * 4)
  $rtb.CopyPixels($bytes, $size * 4, 0)
  return , $bytes
}

function Save-Png([byte[]]$bytes, [int]$w, [int]$h, [string]$path, [double]$scale = 1) {
  $bs = [Windows.Media.Imaging.BitmapSource]::Create($w, $h, 96, 96, [Windows.Media.PixelFormats]::Bgra32, $null, $bytes, $w * 4)
  if ($scale -ne 1) {
    $tb = New-Object Windows.Media.Imaging.TransformedBitmap($bs, (New-Object Windows.Media.ScaleTransform($scale, $scale)))
    $bs = $tb
  }
  $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bs))
  $out = [IO.File]::Create($path)
  try { $enc.Save($out) } finally { $out.Close() }
}

function New-FullEmblem([int]$size) {
  $side = [int][Math]::Ceiling(2 * $r + 2)
  $bytes = Get-Scaled ([int][Math]::Round($cx - $side / 2)) ([int][Math]::Round($cy - $side / 2)) $side $size
  $scale = $size / $side
  $rr = $r * $scale - [Math]::Max(0.6, $size / 256.0)   # slight inset removes the white fringe
  [SltArt]::CircleMask($bytes, $size, $size, $size / 2.0, $size / 2.0, $rr, 1.0)
  return , $bytes
}

function New-HeadIcon([int]$size) {
  $side = [int][Math]::Round($HeadSide * $r * 2)
  $hx = $cx + $HeadX * $r; $hy = $cy + $HeadY * $r
  $bytes = Get-Scaled ([int][Math]::Round($hx - $side / 2)) ([int][Math]::Round($hy - $side / 2)) $side $size
  $c = $size / 2.0
  [SltArt]::CircleMask($bytes, $size, $size, $c, $c, $c - 2.2 * $size / 64, 1.0)
  [SltArt]::Ring($bytes, $size, $size, $c, $c, $c - 0.2, 3.2 * $size / 64, 52, 33, 18)     # dark leather outline
  [SltArt]::Ring($bytes, $size, $size, $c, $c, $c - 0.9 * $size / 64, 1.8 * $size / 64, 212, 168, 82)  # gold band
  return , $bytes
}

# Scales any image file (with or without alpha) to size x size, premultiplied BGRA.
function Get-FileScaled([string]$path, [int]$size) {
  $f = [IO.File]::OpenRead((Resolve-Path $path))
  try {
    $d = [Windows.Media.Imaging.BitmapDecoder]::Create($f, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $img = $d.Frames[0]
  } finally { $f.Close() }
  $dv = New-Object Windows.Media.DrawingVisual
  [Windows.Media.RenderOptions]::SetBitmapScalingMode($dv, [Windows.Media.BitmapScalingMode]::HighQuality)
  $dc = $dv.RenderOpen()
  $dc.DrawImage($img, (New-Object Windows.Rect(0, 0, $size, $size)))
  $dc.Close()
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($size, $size, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($dv)
  $bytes = New-Object byte[] ($size * $size * 4)
  $rtb.CopyPixels($bytes, $size * 4, 0)
  return , $bytes
}

# Comparison sheet on a dark leather background: each icon at 64 px (shown 2x) and at 24 px (shown 4x, minimap size).
function Save-CompareSheet([object[]]$icons, [string]$path) {
  $cell = 220; $sheetW = $cell * $icons.Count; $sheetH = 250
  $dv = New-Object Windows.Media.DrawingVisual
  $dc = $dv.RenderOpen()
  $dc.DrawRectangle((New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(36, 24, 14))), $null, (New-Object Windows.Rect(0, 0, $sheetW, $sheetH)))
  $tf = New-Object Windows.Media.Typeface('Segoe UI')
  $i = 0
  foreach ($ic in $icons) {
    $x0 = $i * $cell + 10
    foreach ($spec in @(@{ s = 64; k = 2; y = 30 }, @{ s = 24; k = 4; y = 30 })) {
      [byte[]]$bytes = & $ic.Make $spec.s
      $bs = [Windows.Media.Imaging.BitmapSource]::Create($spec.s, $spec.s, 96, 96, [Windows.Media.PixelFormats]::Pbgra32, $null, $bytes, $spec.s * 4)
      $big = $spec.s * $spec.k
      $dx = if ($spec.s -eq 64) { $x0 } else { $x0 + 130 }
      $dc.PushGuidelineSet($null)
      [Windows.Media.RenderOptions]::SetBitmapScalingMode($dv, [Windows.Media.BitmapScalingMode]::NearestNeighbor)
      $dc.DrawImage($bs, (New-Object Windows.Rect($dx, $spec.y, $big, $big)))
      $dc.Pop()
    }
    $ft = New-Object Windows.Media.FormattedText($ic.Label, [Globalization.CultureInfo]::InvariantCulture, [Windows.FlowDirection]::LeftToRight, $tf, 15, [Windows.Media.Brushes]::Gold, 1.0)
    $dc.DrawText($ft, (New-Object Windows.Point($x0, 200)))
    $i++
  }
  $dc.Close()
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($sheetW, $sheetH, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($dv)
  $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
  $out = [IO.File]::Create($path)
  try { $enc.Save($out) } finally { $out.Close() }
}

# --- build ---------------------------------------------------------------------------------------------
$logo = New-FullEmblem 256
$logo512 = New-FullEmblem 512
$iconFull = New-FullEmblem 64
$iconHead = New-HeadIcon 64
$tinyHead = New-HeadIcon 32
$iconVector = $null
if ($VectorIcon) { $iconVector = Get-FileScaled $VectorIcon 64 }

if ($Compare) {
  $sets = @(@{ Label = 'Painted: head crop'; Make = { param($s) New-HeadIcon $s } },
            @{ Label = 'Painted: full emblem'; Make = { param($s) New-FullEmblem $s } })
  if ($VectorIcon) { $sets += @{ Label = 'Vector icon'; Make = { param($s) Get-FileScaled $VectorIcon $s } } }
  Save-CompareSheet $sets (Join-Path $previewDir 'compare.png')
}

foreach ($b in @($logo, $logo512, $iconFull, $iconHead, $tinyHead, $iconVector)) { if ($b) { [SltArt]::Unpremultiply($b) } }

Save-Png $logo 256 256 (Join-Path $previewDir 'logo-256.png')
Save-Png $iconHead 64 64 (Join-Path $previewDir 'icon-head-64-x4.png') 4
Save-Png $tinyHead 32 32 (Join-Path $previewDir 'icon-head-32-x6.png') 6

if ($PreviewOnly) { "Previews written to art/preview/ (Media/ and docs/ untouched)"; return }

$icon = switch ($IconStyle) { 'Head' { $iconHead } 'Full' { $iconFull } 'Vector' { if (-not $iconVector) { throw '-IconStyle Vector needs -VectorIcon <file>' }; $iconVector } }
[IO.File]::WriteAllBytes((Join-Path $mediaDir 'SLT_Logo.tga'), [SltArt]::ToTga($logo, 256, 256))
[IO.File]::WriteAllBytes((Join-Path $mediaDir 'SLT_Icon.tga'), [SltArt]::ToTga($icon, 64, 64))
Save-Png $logo512 512 512 (Join-Path $docsDir 'logo.png')
"Wrote Media/SLT_Logo.tga, Media/SLT_Icon.tga ($IconStyle), docs/logo.png and previews in art/preview/"
