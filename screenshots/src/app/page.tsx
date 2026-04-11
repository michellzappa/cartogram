"use client";

import { useState, useRef, useCallback, useEffect } from "react";
import { toPng } from "html-to-image";

type DeviceKind = "phone" | "ipad";

const SIZES = [
  { label: '12.9" iPad', w: 2048, h: 2732, kind: "ipad" },
  { label: '6.9"', w: 1320, h: 2868, kind: "phone" },
  { label: '6.5"', w: 1284, h: 2778, kind: "phone" },
  { label: '6.3"', w: 1206, h: 2622, kind: "phone" },
  { label: '6.1"', w: 1125, h: 2436, kind: "phone" },
] as const;

const MK_W = 1022;
const MK_H = 2082;
const SC_L = (52 / MK_W) * 100;
const SC_T = (46 / MK_H) * 100;
const SC_W = (918 / MK_W) * 100;
const SC_H = (1990 / MK_H) * 100;
const SC_RX = (126 / 918) * 100;
const SC_RY = (126 / 1990) * 100;

const THEME = {
  bg: "#0A0E1A",
  fg: "#F8FAFC",
  accent: "#00D4FF",
  muted: "#64748B",
};

function Phone({ src, alt, style, className = "" }: { src: string; alt: string; style?: React.CSSProperties; className?: string }) {
  return (
    <div className={`relative ${className}`} style={{ aspectRatio: `${MK_W}/${MK_H}`, ...style }}>
      <img src="/mockup.png" alt="" className="block w-full h-full" draggable={false} />
      <div className="absolute z-10 overflow-hidden" style={{ left: `${SC_L}%`, top: `${SC_T}%`, width: `${SC_W}%`, height: `${SC_H}%`, borderRadius: `${SC_RX}% / ${SC_RY}%` }}>
        <img src={src} alt={alt} className="block w-full h-full object-cover object-top" draggable={false} />
      </div>
    </div>
  );
}

function IPad({ src, alt, style, className = "" }: { src: string; alt: string; style?: React.CSSProperties; className?: string }) {
  return (
    <div className={`relative ${className}`} style={{ aspectRatio: "820 / 1100", ...style }}>
      <div
        className="absolute inset-0"
        style={{
          borderRadius: "7%",
          background: "linear-gradient(145deg, #111827 0%, #020617 100%)",
          boxShadow: "0 40px 100px rgba(0, 0, 0, 0.45), inset 0 1px 0 rgba(255,255,255,0.08)",
        }}
      />
      <div
        className="absolute left-1/2 -translate-x-1/2"
        style={{
          top: "1.6%",
          width: "14%",
          height: "1.15%",
          borderRadius: 999,
          background: "rgba(148, 163, 184, 0.28)",
        }}
      />
      <div
        className="absolute overflow-hidden"
        style={{
          left: "4.5%",
          top: "4.25%",
          width: "91%",
          height: "91.5%",
          borderRadius: "4.5%",
          background: "#020617",
        }}
      >
        <img
          src={src}
          alt=""
          className="absolute inset-0 block h-full w-full scale-110 object-cover opacity-35 blur-3xl"
          draggable={false}
        />
        <img
          src={src}
          alt={alt}
          className="relative z-10 block h-full w-full object-contain"
          draggable={false}
        />
      </div>
    </div>
  );
}

function DeviceFrame({
  device,
  src,
  alt,
  style,
  className = "",
}: {
  device: DeviceKind;
  src: string;
  alt: string;
  style?: React.CSSProperties;
  className?: string;
}) {
  if (device === "ipad") {
    return <IPad src={src} alt={alt} style={style} className={className} />;
  }
  return <Phone src={src} alt={alt} style={style} className={className} />;
}

function Caption({ label, headline, canvasW, align = "center", color = THEME.fg, accent = THEME.accent }: { label: string; headline: string; canvasW: number; align?: "center" | "left"; color?: string; accent?: string }) {
  return (
    <div style={{ textAlign: align, padding: `0 ${canvasW * 0.06}px` }}>
      <div style={{ fontSize: canvasW * 0.032, fontWeight: 600, color: accent, textTransform: "uppercase" as const, letterSpacing: "0.12em", marginBottom: canvasW * 0.02 }}>{label}</div>
      <div style={{ fontSize: canvasW * 0.085, fontWeight: 700, lineHeight: 1.0, color }} dangerouslySetInnerHTML={{ __html: headline }} />
    </div>
  );
}

function Slide1({ W, H, device }: { W: number; H: number; device: DeviceKind }) {
  const frameWidth = device === "ipad" ? "90%" : "82%";
  const frameTransform = device === "ipad" ? "translateX(-50%) translateY(8%)" : "translateX(-50%) translateY(14%)";

  return (
    <div style={{ width: W, height: H, background: `radial-gradient(ellipse at 50% 80%, #1A1030 0%, #0F0F19 70%)`, display: "flex", flexDirection: "column", alignItems: "center", position: "relative", overflow: "hidden" }}>
      <div style={{ position: "absolute", bottom: "-10%", left: "50%", transform: "translateX(-50%)", width: "120%", height: "60%", background: "radial-gradient(ellipse, rgba(230,46,138,0.15) 0%, transparent 60%)", pointerEvents: "none" as const }} />
      <div style={{ marginTop: H * 0.06, display: "flex", flexDirection: "column", alignItems: "center", gap: W * 0.02 }}>
        <img src="/app-icon.png" alt="Cartogram" style={{ width: W * 0.16, height: W * 0.16, borderRadius: W * 0.035 }} draggable={false} />
        <div style={{ fontSize: W * 0.055, fontWeight: 700, color: THEME.fg, letterSpacing: "-0.02em" }}>Cartogram</div>
      </div>
      <Caption label="Your photos. Your map." headline="A wallpaper only<br/>you can have." canvasW={W} accent="#E62E8A" />
      <div style={{ position: "absolute", bottom: 0, left: "50%", transform: frameTransform, width: frameWidth }}>
        <DeviceFrame device={device} src="/screenshots/1-hero.png" alt="Hero" />
      </div>
    </div>
  );
}

function Slide2({ W, H, device }: { W: number; H: number; device: DeviceKind }) {
  const frameWidth = device === "ipad" ? "90%" : "82%";
  const frameTransform = device === "ipad" ? "translateX(-50%) translateY(8%)" : "translateX(-50%) translateY(14%)";

  return (
    <div style={{ width: W, height: H, background: `radial-gradient(ellipse at 50% 80%, #2A1C10 0%, #1A1410 70%)`, display: "flex", flexDirection: "column", alignItems: "center", position: "relative", overflow: "hidden" }}>
      <div style={{ position: "absolute", bottom: "-10%", left: "50%", transform: "translateX(-50%)", width: "120%", height: "60%", background: "radial-gradient(ellipse, rgba(255,107,15,0.12) 0%, transparent 60%)", pointerEvents: "none" as const }} />
      <div style={{ marginTop: device === "ipad" ? H * 0.145 : H * 0.18 }}>
        <Caption label="Photo heatmap" headline="Every photo lights<br/>up the map." canvasW={W} accent="#FF6B0F" />
      </div>
      <div style={{ position: "absolute", bottom: 0, left: "50%", transform: frameTransform, width: frameWidth }}>
        <DeviceFrame device={device} src="/screenshots/2-detail.png" alt="Detail" />
      </div>
    </div>
  );
}

function Slide3({ W, H, device }: { W: number; H: number; device: DeviceKind }) {
  const frameWidth = device === "ipad" ? "90%" : "82%";
  const frameTransform = device === "ipad" ? "translateX(-50%) translateY(8%)" : "translateX(-50%) translateY(14%)";

  return (
    <div style={{ width: W, height: H, background: `radial-gradient(ellipse at 50% 80%, #1A2518 0%, #121710 70%)`, display: "flex", flexDirection: "column", alignItems: "center", position: "relative", overflow: "hidden" }}>
      <div style={{ position: "absolute", bottom: "-10%", left: "50%", transform: "translateX(-50%)", width: "120%", height: "60%", background: "radial-gradient(ellipse, rgba(61,215,92,0.12) 0%, transparent 60%)", pointerEvents: "none" as const }} />
      <div style={{ marginTop: device === "ipad" ? H * 0.145 : H * 0.18 }}>
        <Caption label="Five themes" headline="One map.<br/>Five looks." canvasW={W} accent="#3DD75C" />
      </div>
      <div style={{ position: "absolute", bottom: 0, left: "50%", transform: frameTransform, width: frameWidth }}>
        <DeviceFrame device={device} src="/screenshots/3-settings.png" alt="Settings" />
      </div>
    </div>
  );
}

const SLIDES = [
  { id: "hero", label: "Hero", Component: Slide1 },
  { id: "heatmap", label: "Heatmap", Component: Slide2 },
  { id: "themes", label: "Themes", Component: Slide3 },
];

function ScreenshotPreview({ slide, index, sizeIdx, offscreenRefs }: { slide: (typeof SLIDES)[number]; index: number; sizeIdx: number; offscreenRefs: React.MutableRefObject<(HTMLDivElement | null)[]> }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.15);
  const size = SIZES[sizeIdx];

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => { for (const entry of entries) setScale(entry.contentRect.width / size.w); });
    ro.observe(el);
    return () => ro.disconnect();
  }, [size.w]);

  const { Component } = slide;

  const handleExport = useCallback(async () => {
    const el = offscreenRefs.current[index];
    if (!el) return;
    el.style.left = "0px"; el.style.opacity = "1"; el.style.zIndex = "-1";
    const opts = { width: size.w, height: size.h, pixelRatio: 1, cacheBust: true };
    await toPng(el, opts);
    const dataUrl = await toPng(el, opts);
    el.style.left = "-9999px"; el.style.opacity = ""; el.style.zIndex = "";
    const link = document.createElement("a");
    link.download = `${String(index + 1).padStart(2, "0")}-${slide.id}-${size.w}x${size.h}.png`;
    link.href = dataUrl;
    link.click();
  }, [index, slide.id, size, offscreenRefs]);

  return (
    <div className="flex flex-col gap-2">
      <div ref={containerRef} className="relative overflow-hidden rounded-xl bg-black cursor-pointer group" style={{ aspectRatio: `${size.w}/${size.h}` }} onClick={handleExport}>
        <div style={{ transform: `scale(${scale})`, transformOrigin: "top left", width: size.w, height: size.h }}>
          <Component W={size.w} H={size.h} device={size.kind} />
        </div>
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/30 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100">
          <span className="text-white text-sm font-medium bg-black/60 px-3 py-1.5 rounded-full">Export PNG</span>
        </div>
      </div>
      <div className="text-xs text-center text-zinc-500">#{index + 1} {slide.label}</div>
    </div>
  );
}

export default function ScreenshotsPage() {
  const [sizeIdx, setSizeIdx] = useState(0);
  const offscreenRefs = useRef<(HTMLDivElement | null)[]>([]);
  const [exporting, setExporting] = useState(false);

  const exportSize = useCallback(async (size: typeof SIZES[number]) => {
    for (let i = 0; i < SLIDES.length; i++) {
      const el = offscreenRefs.current[i];
      if (!el) continue;
      el.style.width = `${size.w}px`; el.style.height = `${size.h}px`;
      el.style.left = "0px"; el.style.opacity = "1"; el.style.zIndex = "-1";
      const opts = { width: size.w, height: size.h, pixelRatio: 1, cacheBust: true };
      await toPng(el, opts);
      const dataUrl = await toPng(el, opts);
      el.style.left = "-9999px"; el.style.opacity = ""; el.style.zIndex = "";
      el.style.width = `${SIZES[sizeIdx].w}px`; el.style.height = `${SIZES[sizeIdx].h}px`;
      const link = document.createElement("a");
      link.download = `${String(i + 1).padStart(2, "0")}-${SLIDES[i].id}-${size.w}x${size.h}.png`;
      link.href = dataUrl;
      link.click();
      await new Promise((r) => setTimeout(r, 300));
    }
  }, [sizeIdx]);

  const exportAll = useCallback(async () => {
    setExporting(true);
    await exportSize(SIZES[sizeIdx]);
    setExporting(false);
  }, [sizeIdx, exportSize]);

  const exportAllSizes = useCallback(async () => {
    setExporting(true);
    for (const size of SIZES) {
      await exportSize(size);
    }
    setExporting(false);
  }, [exportSize]);

  return (
    <div className="min-h-screen bg-zinc-950 text-white p-8">
      <div className="flex items-center justify-between mb-8">
        <h1 className="text-xl font-bold">Cartogram &mdash; App Store Screenshots</h1>
        <div className="flex items-center gap-4">
          <select value={sizeIdx} onChange={(e) => setSizeIdx(Number(e.target.value))} className="bg-zinc-800 text-white text-sm px-3 py-1.5 rounded-lg border border-zinc-700">
            {SIZES.map((s, i) => (<option key={i} value={i}>{s.label} ({s.w}x{s.h})</option>))}
          </select>
          <button onClick={exportAll} disabled={exporting} className="bg-blue-600 hover:bg-blue-500 disabled:bg-zinc-700 text-white text-sm font-medium px-4 py-1.5 rounded-lg transition-colors">
            {exporting ? "Exporting..." : "Export"}
          </button>
          <button onClick={exportAllSizes} disabled={exporting} className="bg-emerald-600 hover:bg-emerald-500 disabled:bg-zinc-700 text-white text-sm font-medium px-4 py-1.5 rounded-lg transition-colors">
            {exporting ? "Exporting..." : "Export All Sizes"}
          </button>
        </div>
      </div>
      <div className="grid grid-cols-3 gap-6">
        {SLIDES.map((slide, i) => (<ScreenshotPreview key={slide.id} slide={slide} index={i} sizeIdx={sizeIdx} offscreenRefs={offscreenRefs} />))}
      </div>
      {SLIDES.map((slide, i) => {
        const size = SIZES[sizeIdx];
        const { Component } = slide;
        return (
          <div key={`offscreen-${slide.id}`} ref={(el) => { offscreenRefs.current[i] = el; }} style={{ position: "absolute", left: "-9999px", top: 0, width: size.w, height: size.h, fontFamily: "Inter, sans-serif" }}>
            <Component W={size.w} H={size.h} device={size.kind} />
          </div>
        );
      })}
    </div>
  );
}
