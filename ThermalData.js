// Comprehensive thermal reference table for CPU/GPU auto-detection.
//
// Each entry maps a model-name regex to real-world thermal characteristics:
//   idle  – typical desktop idle temp (°C)
//   load  – typical gaming / stress temp (°C)
//   peak  – thermal throttle / TjMax (°C)
//   tjMax – same as peak, used by the color-scale envelope
//
// Tables are checked top-to-bottom; first match wins.  When nothing matches
// the fallback defaults (getDefaultThermal) kick in so the widget still
// colours sensibly on unknown hardware.
.pragma library

// ── CPU thermal table ────────────────────────────────────────────────────────
// Entries from specific → generic so partial matches don't shadow exact ones.
var _cpuTable = [
  // ── AMD Ryzen 9000 (Zen 5) ──
  { re: /ryzen\s*9\s*9950/,  idle: 35, load: 80, peak: 95, tjMax: 95 },
  { re: /ryzen\s*9\s*9900/,  idle: 35, load: 78, peak: 95, tjMax: 95 },
  { re: /ryzen\s*7\s*9700/,  idle: 33, load: 75, peak: 95, tjMax: 95 },
  { re: /ryzen\s*5\s*9600/,  idle: 32, load: 73, peak: 95, tjMax: 95 },

  // ── AMD Ryzen 7000 (Zen 4) ──
  { re: /ryzen\s*9\s*7950/,  idle: 36, load: 82, peak: 95, tjMax: 95 },
  { re: /ryzen\s*9\s*7900/,  idle: 35, load: 80, peak: 95, tjMax: 95 },
  { re: /ryzen\s*7\s*7800/,  idle: 33, load: 76, peak: 95, tjMax: 95 },
  { re: /ryzen\s*7\s*7700/,  idle: 33, load: 77, peak: 95, tjMax: 95 },
  { re: /ryzen\s*5\s*7600/,  idle: 32, load: 74, peak: 95, tjMax: 95 },
  { re: /ryzen\s*5\s*7500/,  idle: 31, load: 72, peak: 95, tjMax: 95 },

  // ── AMD Ryzen 5000 (Zen 3) ──
  { re: /ryzen\s*9\s*5950/,  idle: 34, load: 78, peak: 90, tjMax: 90 },
  { re: /ryzen\s*9\s*5900/,  idle: 34, load: 77, peak: 90, tjMax: 90 },
  { re: /ryzen\s*7\s*5800/,  idle: 33, load: 76, peak: 90, tjMax: 90 },
  { re: /ryzen\s*7\s*5700/,  idle: 32, load: 74, peak: 90, tjMax: 90 },
  { re: /ryzen\s*5\s*5600/,  idle: 31, load: 72, peak: 90, tjMax: 90 },
  { re: /ryzen\s*5\s*5500/,  idle: 30, load: 70, peak: 90, tjMax: 90 },

  // ── AMD Ryzen 3000 (Zen 2) ──
  { re: /ryzen\s*9\s*3950/,  idle: 35, load: 80, peak: 95, tjMax: 95 },
  { re: /ryzen\s*9\s*3900/,  idle: 34, load: 78, peak: 95, tjMax: 95 },
  { re: /ryzen\s*7\s*3800/,  idle: 33, load: 76, peak: 95, tjMax: 95 },
  { re: /ryzen\s*7\s*3700/,  idle: 32, load: 74, peak: 95, tjMax: 95 },
  { re: /ryzen\s*5\s*3600/,  idle: 31, load: 72, peak: 95, tjMax: 95 },
  { re: /ryzen\s*5\s*3500/,  idle: 30, load: 70, peak: 95, tjMax: 95 },

  // ── AMD Ryzen 2000 (Zen+) ──
  { re: /ryzen\s*7\s*2700/,  idle: 33, load: 75, peak: 95, tjMax: 95 },
  { re: /ryzen\s*5\s*2600/,  idle: 31, load: 72, peak: 95, tjMax: 95 },

  // ── AMD Ryzen 1000 (Zen) ──
  { re: /ryzen\s*7\s*1800/,  idle: 35, load: 78, peak: 95, tjMax: 95 },
  { re: /ryzen\s*7\s*1700/,  idle: 33, load: 75, peak: 95, tjMax: 95 },
  { re: /ryzen\s*5\s*1600/,  idle: 32, load: 73, peak: 95, tjMax: 95 },
  { re: /ryzen\s*5\s*1500/,  idle: 30, load: 70, peak: 95, tjMax: 95 },

  // ── AMD Threadripper (sTRX4 / sTR4) ──
  { re: /threadripper\s*7/,   idle: 38, load: 82, peak: 95, tjMax: 95 },
  { re: /threadripper\s*5/,   idle: 37, load: 80, peak: 95, tjMax: 95 },
  { re: /threadripper\s*3/,   idle: 36, load: 78, peak: 95, tjMax: 95 },
  { re: /threadripper\s*2/,   idle: 35, load: 76, peak: 95, tjMax: 95 },
  { re: /threadripper\s*1/,   idle: 35, load: 77, peak: 95, tjMax: 95 },

  // ── AMD EPYC (server, lower clocks) ──
  { re: /epyc/,               idle: 35, load: 72, peak: 90, tjMax: 90 },

  // ── AMD FX / Athlon / older ──
  { re: /fx\s*-9/,            idle: 35, load: 75, peak: 90, tjMax: 90 },
  { re: /fx\s*-8/,            idle: 34, load: 74, peak: 90, tjMax: 90 },
  { re: /fx\s*-6/,            idle: 33, load: 72, peak: 90, tjMax: 90 },
  { re: /fx\s*-4/,            idle: 32, load: 70, peak: 90, tjMax: 90 },
  { re: /athlon/,             idle: 30, load: 65, peak: 85, tjMax: 85 },
  { re: /sempron/,            idle: 28, load: 60, peak: 80, tjMax: 80 },
  { re: /a[0-9]/,             idle: 29, load: 63, peak: 85, tjMax: 85 },

  // ── Generic AMD catch-all (Ryzen AI, unknown APUs, etc.) ──
  { re: /ryzen/,              idle: 33, load: 72, peak: 95, tjMax: 95 },
  { re: /amd/,                idle: 32, load: 70, peak: 90, tjMax: 90 },

  // ── Intel Core Ultra 200S (Arrow Lake) ──
  { re: /ultra\s*9\s*29/,  idle: 34, load: 78, peak: 105, tjMax: 105 },
  { re: /ultra\s*9\s*28/,  idle: 34, load: 78, peak: 105, tjMax: 105 },
  { re: /ultra\s*7\s*26/,  idle: 33, load: 75, peak: 105, tjMax: 105 },
  { re: /ultra\s*7\s*25/,  idle: 33, load: 75, peak: 105, tjMax: 105 },
  { re: /ultra\s*5\s*24/,  idle: 32, load: 72, peak: 105, tjMax: 105 },

  // ── Intel Core Ultra 100 (Meteor Lake) ──
  { re: /ultra\s*9\s*18/,  idle: 34, load: 77, peak: 100, tjMax: 100 },
  { re: /ultra\s*7\s*16/,  idle: 33, load: 74, peak: 100, tjMax: 100 },
  { re: /ultra\s*5\s*13/,  idle: 32, load: 71, peak: 100, tjMax: 100 },

  // ── Intel 14th Gen (Raptor Lake Refresh) ──
  { re: /i9.*149/,   idle: 36, load: 82, peak: 100, tjMax: 100 },
  { re: /i9.*1490/,  idle: 36, load: 82, peak: 100, tjMax: 100 },
  { re: /i7.*147/,   idle: 34, load: 78, peak: 100, tjMax: 100 },
  { re: /i7.*1470/,  idle: 34, load: 78, peak: 100, tjMax: 100 },
  { re: /i5.*146/,   idle: 33, load: 75, peak: 100, tjMax: 100 },
  { re: /i5.*1450/,  idle: 33, load: 74, peak: 100, tjMax: 100 },
  { re: /i5.*144/,   idle: 32, load: 72, peak: 100, tjMax: 100 },
  { re: /i5.*1440/,  idle: 32, load: 72, peak: 100, tjMax: 100 },

  // ── Intel 13th Gen (Raptor Lake) ──
  { re: /i9.*139/,   idle: 36, load: 82, peak: 100, tjMax: 100 },
  { re: /i9.*1390/,  idle: 36, load: 82, peak: 100, tjMax: 100 },
  { re: /i7.*137/,   idle: 34, load: 78, peak: 100, tjMax: 100 },
  { re: /i7.*1370/,  idle: 34, load: 78, peak: 100, tjMax: 100 },
  { re: /i5.*136/,   idle: 33, load: 75, peak: 100, tjMax: 100 },
  { re: /i5.*1350/,  idle: 33, load: 74, peak: 100, tjMax: 100 },
  { re: /i5.*134/,   idle: 32, load: 72, peak: 100, tjMax: 100 },
  { re: /i5.*1340/,  idle: 32, load: 72, peak: 100, tjMax: 100 },

  // ── Intel 12th Gen (Alder Lake) ──
  { re: /i9.*129/,   idle: 35, load: 80, peak: 100, tjMax: 100 },
  { re: /i9.*1290/,  idle: 35, load: 80, peak: 100, tjMax: 100 },
  { re: /i7.*127/,   idle: 33, load: 76, peak: 100, tjMax: 100 },
  { re: /i7.*1270/,  idle: 33, load: 76, peak: 100, tjMax: 100 },
  { re: /i5.*126/,   idle: 32, load: 73, peak: 100, tjMax: 100 },
  { re: /i5.*1250/,  idle: 32, load: 72, peak: 100, tjMax: 100 },
  { re: /i5.*124/,   idle: 31, load: 70, peak: 100, tjMax: 100 },
  { re: /i5.*1240/,  idle: 31, load: 70, peak: 100, tjMax: 100 },

  // ── Intel 11th Gen (Rocket Lake) ──
  { re: /i9.*119/,   idle: 35, load: 80, peak: 100, tjMax: 100 },
  { re: /i7.*117/,   idle: 33, load: 76, peak: 100, tjMax: 100 },
  { re: /i5.*116/,   idle: 32, load: 73, peak: 100, tjMax: 100 },
  { re: /i5.*114/,   idle: 31, load: 70, peak: 100, tjMax: 100 },

  // ── Intel 10th Gen (Comet Lake) ──
  { re: /i9.*109/,   idle: 35, load: 80, peak: 100, tjMax: 100 },
  { re: /i7.*107/,   idle: 33, load: 76, peak: 100, tjMax: 100 },
  { re: /i5.*106/,   idle: 32, load: 73, peak: 100, tjMax: 100 },
  { re: /i5.*105/,   idle: 31, load: 70, peak: 100, tjMax: 100 },

  // ── Intel 9th Gen (Coffee Lake Refresh) ──
  { re: /i9.*99/,    idle: 35, load: 80, peak: 100, tjMax: 100 },
  { re: /i7.*97/,    idle: 33, load: 76, peak: 100, tjMax: 100 },
  { re: /i5.*96/,    idle: 32, load: 73, peak: 100, tjMax: 100 },
  { re: /i5.*94/,    idle: 31, load: 70, peak: 100, tjMax: 100 },

  // ── Intel 8th Gen (Coffee Lake) ──
  { re: /i7.*87/,    idle: 33, load: 76, peak: 100, tjMax: 100 },
  { re: /i5.*86/,    idle: 32, load: 73, peak: 100, tjMax: 100 },
  { re: /i5.*85/,    idle: 31, load: 70, peak: 100, tjMax: 100 },

  // ── Intel 7th Gen & older (Kaby Lake / Sky Lake / Broadwell …) ──
  { re: /i7.*77/,    idle: 33, load: 75, peak: 100, tjMax: 100 },
  { re: /i5.*76/,    idle: 32, load: 72, peak: 100, tjMax: 100 },
  { re: /i5.*75/,    idle: 31, load: 70, peak: 100, tjMax: 100 },
  { re: /i7.*67/,    idle: 33, load: 75, peak: 100, tjMax: 100 },
  { re: /i5.*66/,    idle: 32, load: 72, peak: 100, tjMax: 100 },
  { re: /i5.*65/,    idle: 31, load: 70, peak: 100, tjMax: 100 },

  // ── Intel generic fallbacks by tier ──
  { re: /core\s*i9/,  idle: 35, load: 80, peak: 100, tjMax: 100 },
  { re: /core\s*i7/,  idle: 33, load: 76, peak: 100, tjMax: 100 },
  { re: /core\s*i5/,  idle: 32, load: 73, peak: 100, tjMax: 100 },
  { re: /core\s*i3/,  idle: 30, load: 68, peak: 100, tjMax: 100 },
  { re: /pentium/,    idle: 28, load: 60, peak: 90,  tjMax: 90  },
  { re: /celeron/,    idle: 27, load: 58, peak: 85,  tjMax: 85  },

  // ── Catch-all Intel ──
  { re: /intel/,      idle: 32, load: 72, peak: 100, tjMax: 100 }
]

// ── GPU thermal table ────────────────────────────────────────────────────────
var _gpuTable = [
  // ── NVIDIA RTX 50 Series (Blackwell) ──
  { re: /rtx\s*5090/,  idle: 35, load: 75, peak: 90, tjMax: 90 },
  { re: /rtx\s*5080/,  idle: 34, load: 73, peak: 90, tjMax: 90 },
  { re: /rtx\s*5070\s*t[i]?/, idle: 33, load: 72, peak: 90, tjMax: 90 },
  { re: /rtx\s*5070/,  idle: 33, load: 71, peak: 90, tjMax: 90 },
  { re: /rtx\s*5060\s*t[i]?/, idle: 32, load: 70, peak: 90, tjMax: 90 },
  { re: /rtx\s*5060/,  idle: 32, load: 69, peak: 90, tjMax: 90 },

  // ── NVIDIA RTX 40 Series (Ada Lovelace) ──
  { re: /rtx\s*4090/,  idle: 36, load: 76, peak: 90, tjMax: 90 },
  { re: /rtx\s*4080\s*s/, idle: 35, load: 74, peak: 90, tjMax: 90 },
  { re: /rtx\s*4080/,  idle: 35, load: 73, peak: 90, tjMax: 90 },
  { re: /rtx\s*4070\s*t[i]?/, idle: 34, load: 72, peak: 90, tjMax: 90 },
  { re: /rtx\s*4070\s*s/, idle: 33, load: 71, peak: 90, tjMax: 90 },
  { re: /rtx\s*4070/,  idle: 33, load: 70, peak: 90, tjMax: 90 },
  { re: /rtx\s*4060\s*t[i]?/, idle: 32, load: 68, peak: 90, tjMax: 90 },
  { re: /rtx\s*4060/,  idle: 32, load: 67, peak: 90, tjMax: 90 },

  // ── NVIDIA RTX 30 Series (Ampere) ──
  { re: /rtx\s*3090/,  idle: 36, load: 78, peak: 93, tjMax: 93 },
  { re: /rtx\s*3080/,  idle: 35, load: 77, peak: 93, tjMax: 93 },
  { re: /rtx\s*3070/,  idle: 34, load: 75, peak: 93, tjMax: 93 },
  { re: /rtx\s*3060\s*ti/, idle: 33, load: 73, peak: 93, tjMax: 93 },
  { re: /rtx\s*3060/,  idle: 32, load: 71, peak: 93, tjMax: 93 },

  // ── NVIDIA RTX 20 Series (Turing) ──
  { re: /rtx\s*2080\s*t[i]?/, idle: 35, load: 76, peak: 88, tjMax: 88 },
  { re: /rtx\s*2080/,  idle: 34, load: 75, peak: 88, tjMax: 88 },
  { re: /rtx\s*2070\s*s/, idle: 33, load: 73, peak: 88, tjMax: 88 },
  { re: /rtx\s*2070/,  idle: 33, load: 72, peak: 88, tjMax: 88 },
  { re: /rtx\s*2060\s*s/, idle: 32, load: 71, peak: 88, tjMax: 88 },
  { re: /rtx\s*2060/,  idle: 32, load: 70, peak: 88, tjMax: 88 },

  // ── NVIDIA GTX 16 Series (Turing, no RT) ──
  { re: /gtx\s*1660\s*t[i]?/, idle: 31, load: 68, peak: 83, tjMax: 83 },
  { re: /gtx\s*1660\s*s/, idle: 31, load: 67, peak: 83, tjMax: 83 },
  { re: /gtx\s*1660/,  idle: 31, load: 67, peak: 83, tjMax: 83 },
  { re: /gtx\s*1650\s*s/, idle: 30, load: 65, peak: 83, tjMax: 83 },
  { re: /gtx\s*1650/,  idle: 30, load: 64, peak: 83, tjMax: 83 },

  // ── NVIDIA GTX 10 Series (Pascal) ──
  { re: /gtx\s*1080\s*ti/, idle: 35, load: 76, peak: 84, tjMax: 84 },
  { re: /gtx\s*1080/,  idle: 34, load: 74, peak: 83, tjMax: 83 },
  { re: /gtx\s*1070\s*ti/, idle: 33, load: 73, peak: 84, tjMax: 84 },
  { re: /gtx\s*1070/,  idle: 33, load: 72, peak: 83, tjMax: 83 },
  { re: /gtx\s*1060/,  idle: 31, load: 68, peak: 83, tjMax: 83 },
  { re: /gtx\s*1050\s*ti/, idle: 30, load: 65, peak: 83, tjMax: 83 },
  { re: /gtx\s*1050/,  idle: 29, load: 63, peak: 83, tjMax: 83 },

  // ── NVIDIA GTX 9 Series (Maxwell) ──
  { re: /gtx\s*980\s*ti/, idle: 34, load: 74, peak: 83, tjMax: 83 },
  { re: /gtx\s*980/,   idle: 33, load: 72, peak: 83, tjMax: 83 },
  { re: /gtx\s*970/,   idle: 32, load: 70, peak: 83, tjMax: 83 },
  { re: /gtx\s*960/,   idle: 30, load: 66, peak: 83, tjMax: 83 },
  { re: /gtx\s*950/,   idle: 29, load: 64, peak: 83, tjMax: 83 },

  // ── NVIDIA older / generic ──
  { re: /geforce\s*gtx/,  idle: 32, load: 70, peak: 85, tjMax: 85 },
  { re: /geforce\s*rtx/,  idle: 34, load: 74, peak: 90, tjMax: 90 },
  { re: /nvidia.*geforce/, idle: 32, load: 70, peak: 85, tjMax: 85 },
  { re: /nvidia/,         idle: 33, load: 72, peak: 85, tjMax: 85 },

  // ── AMD Radeon RX 9000 (RDNA 4) ──
  { re: /rx\s*9070\s*xt/, idle: 34, load: 72, peak: 85, tjMax: 85 },
  { re: /rx\s*9070/,      idle: 33, load: 70, peak: 85, tjMax: 85 },

  // ── AMD Radeon RX 7000 (RDNA 3) ──
  { re: /rx\s*7900\s*xtx/, idle: 36, load: 76, peak: 85, tjMax: 85 },
  { re: /rx\s*7900\s*xt/,  idle: 35, load: 74, peak: 85, tjMax: 85 },
  { re: /rx\s*7900\s*gre/, idle: 34, load: 72, peak: 85, tjMax: 85 },
  { re: /rx\s*7800\s*xt/,  idle: 34, load: 73, peak: 85, tjMax: 85 },
  { re: /rx\s*7700\s*xt/,  idle: 33, load: 71, peak: 85, tjMax: 85 },
  { re: /rx\s*7600\s*xt/,  idle: 32, load: 69, peak: 85, tjMax: 85 },
  { re: /rx\s*7600/,       idle: 32, load: 68, peak: 85, tjMax: 85 },

  // ── AMD Radeon RX 6000 (RDNA 2) ──
  { re: /rx\s*6950\s*xt/, idle: 36, load: 78, peak: 80, tjMax: 80 },
  { re: /rx\s*6900\s*xt/, idle: 35, load: 76, peak: 80, tjMax: 80 },
  { re: /rx\s*6800\s*xt/, idle: 34, load: 74, peak: 80, tjMax: 80 },
  { re: /rx\s*6800/,      idle: 33, load: 72, peak: 80, tjMax: 80 },
  { re: /rx\s*6750\s*xt/, idle: 33, load: 72, peak: 80, tjMax: 80 },
  { re: /rx\s*6700\s*xt/, idle: 32, load: 70, peak: 80, tjMax: 80 },
  { re: /rx\s*6650\s*xt/, idle: 31, load: 68, peak: 80, tjMax: 80 },
  { re: /rx\s*6600\s*xt/, idle: 31, load: 67, peak: 80, tjMax: 80 },
  { re: /rx\s*6600/,      idle: 30, load: 65, peak: 80, tjMax: 80 },

  // ── AMD Radeon RX 5000 (RDNA 1) ──
  { re: /rx\s*5700\s*xt/, idle: 34, load: 74, peak: 85, tjMax: 85 },
  { re: /rx\s*5700/,      idle: 33, load: 72, peak: 85, tjMax: 85 },
  { re: /rx\s*5600\s*xt/, idle: 32, load: 70, peak: 85, tjMax: 85 },
  { re: /rx\s*5500\s*xt/, idle: 31, load: 68, peak: 85, tjMax: 85 },

  // ── AMD Radeon RX 500 (Polaris) ──
  { re: /rx\s*590/,   idle: 33, load: 72, peak: 85, tjMax: 85 },
  { re: /rx\s*580/,   idle: 32, load: 71, peak: 85, tjMax: 85 },
  { re: /rx\s*570/,   idle: 31, load: 69, peak: 85, tjMax: 85 },
  { re: /rx\s*560/,   idle: 30, load: 66, peak: 85, tjMax: 85 },
  { re: /rx\s*550/,   idle: 29, load: 63, peak: 85, tjMax: 85 },

  // ── AMD Radeon RX Vega ──
  { re: /vega\s*64/,  idle: 35, load: 76, peak: 85, tjMax: 85 },
  { re: /vega\s*56/,  idle: 34, load: 74, peak: 85, tjMax: 85 },

  // ── AMD older / generic ──
  { re: /radeon\s*rx/,   idle: 32, load: 70, peak: 85, tjMax: 85 },
  { re: /radeon.*amd/,   idle: 32, load: 70, peak: 85, tjMax: 85 },
  { re: /amd.*radeon/,   idle: 32, load: 70, peak: 85, tjMax: 85 },

  // ── Intel Arc (Alchemist / Battlemage) ──
  { re: /arc\s*a770/,    idle: 33, load: 72, peak: 85, tjMax: 85 },
  { re: /arc\s*a750/,    idle: 32, load: 70, peak: 85, tjMax: 85 },
  { re: /arc\s*a580/,    idle: 31, load: 68, peak: 85, tjMax: 85 },
  { re: /arc\s*a380/,    idle: 30, load: 65, peak: 85, tjMax: 85 },
  { re: /arc\s*b580/,    idle: 32, load: 70, peak: 85, tjMax: 85 },
  { re: /arc\s*b570/,    idle: 31, load: 68, peak: 85, tjMax: 85 },
  { re: /intel\s*arc/,   idle: 32, load: 70, peak: 85, tjMax: 85 },

  // ── Intel integrated (catch-all, rarely have temp sensors) ──
  { re: /intel.*uhd/,    idle: 30, load: 65, peak: 80, tjMax: 80 },
  { re: /intel.*iris/,   idle: 30, load: 65, peak: 80, tjMax: 80 },
  { re: /intel.*hd/,     idle: 28, load: 62, peak: 78, tjMax: 78 }
]

// ── Fallback defaults ────────────────────────────────────────────────────────
var _defaultCpu = { idle: 33, load: 72, peak: 95, tjMax: 95 }
var _defaultGpu = { idle: 33, load: 72, peak: 85, tjMax: 85 }

// ── Public API ───────────────────────────────────────────────────────────────

// Look up a CPU model string. Returns { idle, load, peak, tjMax } or the
// generic fallback when nothing matches.
function detectCpu(model) {
  var m = (model || "").toLowerCase()
  for (var i = 0; i < _cpuTable.length; i++) {
    if (_cpuTable[i].re.test(m)) return _cpuTable[i]
  }
  return _defaultCpu
}

// Look up a GPU model string. Returns { idle, load, peak, tjMax } or the
// generic fallback when nothing matches.
function detectGpu(model) {
  var m = (model || "").toLowerCase()
  for (var i = 0; i < _gpuTable.length; i++) {
    if (_gpuTable[i].re.test(m)) return _gpuTable[i]
  }
  return _defaultGpu
}

// Bare TjMax helpers (kept for backward-compat with StatsService).
function cpuTjMax(model)  { return detectCpu(model).tjMax }
function gpuTjMax(model)  { return detectGpu(model).tjMax }

// Fallback thermal envelopes — used when hardware is completely unknown.
function getDefaultCpu() { return _defaultCpu }
function getDefaultGpu() { return _defaultGpu }
