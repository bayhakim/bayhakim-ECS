const fields = [
  ["productCode", "Urun Kodu", ["urunkodu", "urunkod", "kod", "code", "productcode", "stok_kodu", "stockcode"]],
  ["model", "Model", ["model", "anaurun", "group", "urunmodel", "maincode"]],
  ["title", "Urun Basligi", ["urunbasligi", "baslik", "title", "name", "urunadi", "productname"]],
  ["brand", "Marka", ["marka", "brand"]],
  ["description", "Aciklama", ["aciklama", "description", "desc"]],
  ["color", "Renk", ["renk", "color", "colour"]],
  ["size", "Beden", ["beden", "size", "numara"]],
  ["barcode", "Barkod", ["barkod", "barcode", "ean"]],
  ["purchasePrice", "Alis Fiyati", ["alisfiyati", "alis", "purchase", "buyprice"]],
  ["costPrice", "Maliyet Fiyati", ["maliyetfiyati", "maliyet", "cost", "costprice"]],
  ["salePrice", "Satis Fiyati", ["satisfiyati", "satis", "sale", "price", "saleprice"]],
  ["listPrice", "Liste Fiyati", ["listefiyati", "listprice", "marketprice"]],
  ["stock", "Kalan Stok", ["kalanmiktar", "kalanstok", "stok", "stock", "quantity", "miktar"]],
  ["image", "Resim", ["images", "image", "resim", "foto", "picture"]]
];

const demoRows = [
  { UrunKodu: "FJ7126-102", Model: "FJ7126", UrunBasligi: "Nike Free kosu ayakkabisi", Marka: "Nike", Aciklama: "Hafif kosu modeli", Renk: "Beyaz", Beden: "40", Barkod: "197599685630", AlisFiyati: 3015.15, MaliyetFiyati: 3015.15, SatisFiyati: 7999.99, ListeFiyati: 13333.9, KalanMiktar: 4, Images: "" },
  { UrunKodu: "FJ7126-102", Model: "FJ7126", UrunBasligi: "Nike Free kosu ayakkabisi", Marka: "Nike", Aciklama: "Hafif kosu modeli", Renk: "Beyaz", Beden: "41", Barkod: "197599685647", AlisFiyati: 3015.15, MaliyetFiyati: 3015.15, SatisFiyati: 7999.99, ListeFiyati: 13333.9, KalanMiktar: 2, Images: "" },
  { UrunKodu: "FJ7126-001", Model: "FJ7126", UrunBasligi: "Nike Free kosu ayakkabisi", Marka: "Nike", Aciklama: "Hafif kosu modeli", Renk: "Siyah", Beden: "42", Barkod: "197599685654", AlisFiyati: 3015.15, MaliyetFiyati: 3015.15, SatisFiyati: 7799.99, ListeFiyati: 12999.9, KalanMiktar: 0, Images: "" },
  { UrunKodu: "DD1503-101", Model: "DD1503", UrunBasligi: "Nike Dunk Low", Marka: "Nike", Aciklama: "Lifestyle sneaker", Renk: "Yesil", Beden: "38", Barkod: "195243322101", AlisFiyati: 2450, MaliyetFiyati: 2520, SatisFiyati: 6499.99, ListeFiyati: 8999.9, KalanMiktar: 7, Images: "" },
  { UrunKodu: "DD1503-101", Model: "DD1503", UrunBasligi: "Nike Dunk Low", Marka: "Nike", Aciklama: "Lifestyle sneaker", Renk: "Yesil", Beden: "39", Barkod: "195243322118", AlisFiyati: 2450, MaliyetFiyati: 2520, SatisFiyati: 6499.99, ListeFiyati: 8999.9, KalanMiktar: 1, Images: "" }
];

let schemaRows = [];
let previewRows = [];
let models = [];
let visibleModels = [];
let selectedModel = null;
let currentSource = "sql";
const imageBaseUrl = "https://cdn.avrupayakasi.com/";
let platformRequestId = 0;
let missingAttributeRows = [];
let selectedMissingAttribute = null;
let missingAttributeGroupsLoaded = false;
let reportBrandsLoaded = false;
let reportBrands = [];
let brandSearchTimer = null;
let stockLocationRows = [];
let stockDetailRows = [];
const stockMatrixGroups = ["LVT-TEKS-001", "LVT-AYK-001", "LVT-ÇNT-001", "MULTIBRAND-001", "Depo"];

const $ = (id) => document.getElementById(id);
const normalize = (text) => (text || "").toString().toLowerCase().replace(/[^a-z0-9]/g, "");

async function api(path, options) {
  const url = path.includes("?") ? `${path}&_=${Date.now()}` : `${path}?_=${Date.now()}`;
  const res = await fetch(url, { ...(options || {}), cache: "no-store" });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "Istek tamamlanamadi");
  return data;
}

function setNotice(text) {
  $("permissionNotice").textContent = text;
  $("permissionNotice").classList.toggle("hidden", !text);
}

async function refreshStatus() {
  const data = await api("/api/status");
  $("status").innerHTML = data.databases.map((db) => {
    const info = db.info || {};
    const hasDataAccess = db.ok && Number(info.database_select) === 1;
    const connected = db.ok ? "Baglandi" : "Baglanamadi";
    const permission = db.ok ? `SELECT: ${info.database_select}, VIEW: ${info.view_definition}` : db.error;
    return `<div class="status-item ${hasDataAccess ? "ok" : "warn"}">
      <strong>${db.database}</strong>
      <span>${connected}</span>
      <span>${permission}</span>
    </div>`;
  }).join("");
  $("database").innerHTML = data.databases.map((db) => `<option value="${db.database}">${db.database}</option>`).join("");
}

async function loadSchema() {
  currentSource = "sql";
  setNotice("");
  $("table").innerHTML = "";
  $("mapping").innerHTML = "";
  schemaRows = [];
  previewRows = [];
  models = [];
  selectedModel = null;
  renderModels();
  renderDetail();

  try {
    const database = $("database").value;
    const data = await api(`/api/schema?database=${encodeURIComponent(database)}`);
    schemaRows = data.columns || [];
    if (!schemaRows.length) {
      setNotice("DB baglantisi var ama bu kullanici tablo/kolon okuyamiyor. Izin acilana kadar 'Demo Veriyi Ac' ile panel akisini test edebiliriz.");
      return;
    }
    const tables = [...new Map(schemaRows.map((r) => [`${r.schema_name}.${r.table_name}`, r])).values()];
    $("table").innerHTML = tables.map((t) => `<option value="${t.schema_name}.${t.table_name}">${t.schema_name}.${t.table_name} (${t.row_count || 0})</option>`).join("");
    await loadPreview();
  } catch (err) {
    setNotice(err.message);
  }
}

async function loadPreview() {
  if (!$("table").value) {
    setNotice("Once tablo secimi gerekiyor. Tablo yoksa yetki eksik demektir.");
    return;
  }
  const [schema, table] = $("table").value.split(".");
  const database = $("database").value;
  const data = await api(`/api/preview?database=${encodeURIComponent(database)}&schema=${encodeURIComponent(schema)}&table=${encodeURIComponent(table)}`);
  previewRows = data.rows || [];
  renderMapping();
}

function loadDemo() {
  currentSource = "demo";
  setNotice("Demo veri acik. SQL izni gelince Kolonlari Getir ile gercek tabloya gececegiz.");
  $("table").innerHTML = `<option value="demo.products">demo.products (${demoRows.length})</option>`;
  previewRows = demoRows;
  renderMapping();
  buildFromRows(previewRows, getMapping());
}

async function loadLiveProducts() {
  currentSource = "live";
  setNotice("Canli urunler yukleniyor. Ilk acilista son 300 varyant getiriyoruz; arama kutusuna model, barkod veya urun kodu yazip Canli Ara ile daraltabilirsin.");
  const search = $("search").value.trim();
  const take = search ? 1000 : 300;
  const data = await api(`/api/ecd-products?take=${take}&search=${encodeURIComponent(search)}`);
  models = hydrateModels(data.models || []);
  selectedModel = models[0] || null;
  renderModels();
  renderDetail();
  setNotice(models.length ? `Canli veri geldi: ${models.length} model.` : "Canli sorgu sonucunda urun bulunamadi.");
}

function hydrateModels(sourceModels) {
  return sourceModels.map((model) => {
    const variants = model.variants || [];
    const stockTotal = variants.reduce((sum, item) => sum + numeric(item.stock), 0);
    const stockValue = variants.reduce((sum, item) => sum + numeric(item.stock) * numeric(item.salePrice), 0);
    const costValue = variants.reduce((sum, item) => sum + numeric(item.stock) * numeric(item.costPrice), 0);
    return {
      ...model,
      description: model.description || firstValue(variants, "description"),
      stockTotal,
      stockValue,
      costValue
    };
  });
}

function guessColumn(key, columns) {
  const field = fields.find((f) => f[0] === key);
  const aliases = field ? field[2] : [];
  const normalized = columns.map((c) => ({ raw: c, norm: normalize(c) }));
  for (const alias of aliases) {
    const exact = normalized.find((c) => c.norm === normalize(alias));
    if (exact) return exact.raw;
  }
  for (const alias of aliases) {
    const partial = normalized.find((c) => c.norm.includes(normalize(alias)) || normalize(alias).includes(c.norm));
    if (partial) return partial.raw;
  }
  return "";
}

function renderMapping() {
  const columns = previewRows[0] ? Object.keys(previewRows[0]) : schemaRows.filter((r) => `${r.schema_name}.${r.table_name}` === $("table").value).map((r) => r.column_name);
  $("mapping").innerHTML = fields.map(([key, label]) => {
    const guessed = guessColumn(key, columns);
    const opts = [`<option value="">Bos</option>`].concat(columns.map((c) => `<option value="${escapeHtml(c)}" ${c === guessed ? "selected" : ""}>${escapeHtml(c)}</option>`));
    return `<div class="field"><label>${label}</label><select data-map="${key}">${opts.join("")}</select></div>`;
  }).join("");
}

function getMapping() {
  const mapping = {};
  document.querySelectorAll("[data-map]").forEach((el) => mapping[el.dataset.map] = el.value);
  return mapping;
}

async function buildPanel() {
  setNotice("");
  if (currentSource === "demo") {
    buildFromRows(previewRows, getMapping());
    return;
  }
  if (!$("table").value) {
    setNotice("Tablo listesi bos. SQL okuma izni acildiginda paneli gercek veriyle olusturabiliriz.");
    return;
  }
  const [schema, table] = $("table").value.split(".");
  const payload = { database: $("database").value, schema, table, mapping: getMapping(), take: 2000 };
  const data = await api("/api/products", {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify(payload)
  });
  models = data.models || [];
  selectedModel = models[0] || null;
  renderModels();
  renderDetail();
}

function buildFromRows(rows, mapping) {
  const variants = rows.map((row) => {
    const productCode = row[mapping.productCode];
    let model = row[mapping.model];
    if (!model) {
      const codeText = String(productCode || "");
      model = codeText.includes("-") ? codeText.split("-")[0] : codeText;
    }
    return {
      model,
      productCode,
      title: row[mapping.title],
      brand: row[mapping.brand],
      description: row[mapping.description],
      color: row[mapping.color],
      size: row[mapping.size],
      barcode: row[mapping.barcode],
      purchasePrice: row[mapping.purchasePrice],
      costPrice: row[mapping.costPrice],
      salePrice: row[mapping.salePrice],
      listPrice: row[mapping.listPrice],
      stock: row[mapping.stock],
      image: row[mapping.image],
      raw: row
    };
  });

  const grouped = new Map();
  for (const item of variants) {
    const key = item.model || "Modelsiz";
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key).push(item);
  }
  models = [...grouped.entries()].map(([model, items]) => {
    const stockTotal = items.reduce((sum, item) => sum + numeric(item.stock), 0);
    return {
      model,
      title: firstValue(items, "title"),
      brand: firstValue(items, "brand"),
      image: firstValue(items, "image"),
      description: firstValue(items, "description"),
      variantCount: items.length,
      stockTotal,
      stockValue: items.reduce((sum, item) => sum + numeric(item.stock) * numeric(item.salePrice), 0),
      costValue: items.reduce((sum, item) => sum + numeric(item.stock) * numeric(item.costPrice), 0),
      colors: unique(items.map((x) => x.color).filter(Boolean)),
      sizes: unique(items.map((x) => x.size).filter(Boolean)),
      variants: items
    };
  }).sort((a, b) => String(a.model).localeCompare(String(b.model)));
  selectedModel = models[0] || null;
  renderModels();
  renderDetail();
}

function renderModels() {
  const q = normalize($("search").value);
  const stockFilter = $("stockFilter") ? $("stockFilter").value : "all";
  const sortBy = $("sortBy") ? $("sortBy").value : "model";
  let filtered = models.filter((m) => {
    const text = normalize([m.model, m.title, m.brand, ...(m.colors || []), ...(m.sizes || [])].join(" "));
    const searchOk = !q || text.includes(q);
    const stocks = (m.variants || []).map((v) => numeric(v.stock));
    const stockOk =
      stockFilter === "all" ||
      (stockFilter === "in" && stocks.some((x) => x > 0)) ||
      (stockFilter === "low" && stocks.some((x) => x > 0 && x <= 2)) ||
      (stockFilter === "out" && stocks.every((x) => x <= 0));
    return searchOk && stockOk;
  });
  filtered = sortModels(filtered, sortBy);
  visibleModels = filtered;
  const totals = summarizeModels(filtered);
  $("modelCount").textContent = filtered.length;
  $("variantCount").textContent = totals.variantCount;
  $("stockTotal").textContent = totals.stockTotal;
  $("stockValue").textContent = formatCompactMoney(totals.stockValue);
  $("costValue").textContent = formatCompactMoney(totals.costValue);
  $("profitValue").textContent = formatCompactMoney(totals.stockValue - totals.costValue);
  if (selectedModel && !filtered.some((m) => m.model === selectedModel.model)) {
    selectedModel = filtered[0] || null;
  }
  $("modelList").innerHTML = filtered.map((m) => `<div class="model-item ${selectedModel && selectedModel.model === m.model ? "active" : ""}" data-model="${escapeAttr(m.model)}">
    <div class="model-thumb">${renderImage(m.image, "")}</div>
    <div>
      <strong>${escapeHtml(m.model || "Modelsiz")}</strong>
      <small>${escapeHtml(m.brand || "")} ${m.variantCount || 0} varyant - ${m.stockTotal || 0} stok - ${formatCompactMoney((m.stockValue || 0) - (m.costValue || 0))} kar</small>
    </div>
  </div>`).join("");
  document.querySelectorAll(".model-item").forEach((el) => el.addEventListener("click", () => {
    selectedModel = models.find((m) => String(m.model) === el.dataset.model);
    renderModels();
    renderDetail();
  }));
}

function renderDetail() {
  $("detailEmpty").classList.toggle("hidden", !!selectedModel);
  $("detail").classList.toggle("hidden", !selectedModel);
  if (!selectedModel) return;
  $("detailModel").textContent = selectedModel.model || "Modelsiz";
  $("detailTitle").textContent = [selectedModel.brand, selectedModel.title].filter(Boolean).join(" - ");
  $("chips").innerHTML = [
    `${selectedModel.variantCount || 0} varyant`,
    `${selectedModel.stockTotal || 0} stok`,
    ...(selectedModel.colors || []).slice(0, 8),
    ...(selectedModel.sizes || []).slice(0, 8)
  ].map((x) => `<span>${escapeHtml(x)}</span>`).join("");
  const imageUrl = resolveImageUrl(selectedModel.image);
  $("imageBox").innerHTML = imageUrl ? `<a href="${escapeAttr(imageUrl)}" target="_blank" rel="noreferrer">${renderImage(selectedModel.image, selectedModel.model)}</a>` : "Resim yok";
  const metrics = summarizeModels([selectedModel]);
  $("detailMetrics").innerHTML = [
    ["Satis Degeri", formatMoney(metrics.stockValue)],
    ["Maliyet", formatMoney(metrics.costValue)],
    ["Tahmini Kar", formatMoney(metrics.stockValue - metrics.costValue)],
    ["Ortalama Marj", `${formatPercent((metrics.stockValue - metrics.costValue) / metrics.stockValue)}%`]
  ].map(([label, value]) => `<div><strong>${escapeHtml(value)}</strong><span>${escapeHtml(label)}</span></div>`).join("");
  const desc = cleanDescription(selectedModel.description);
  $("detailDescription").textContent = desc.length > 260 ? `${desc.slice(0, 260)}...` : desc;
  $("detailDescription").classList.toggle("hidden", !desc);
  $("variantRows").innerHTML = (selectedModel.variants || []).map((v) => {
    const margin = numeric(v.salePrice) - numeric(v.costPrice);
    const rowClass = numeric(v.stock) <= 0 ? "out-stock" : numeric(v.stock) <= 2 ? "low-stock" : "";
    return `<tr class="${rowClass}">
      <td>${escapeHtml(v.productCode)}</td>
      <td>${escapeHtml(v.color)}</td>
      <td>${escapeHtml(v.size)}</td>
      <td>${escapeHtml(v.barcode)}</td>
      <td>${formatMoney(v.purchasePrice)}</td>
      <td>${formatMoney(v.costPrice)}</td>
      <td>${formatMoney(v.salePrice)}</td>
      <td>${formatMoney(v.listPrice)}</td>
      <td>${escapeHtml(v.stock)}</td>
      <td>${formatMoney(margin)}</td>
    </tr>`;
  }).join("");
  loadPlatformRows(selectedModel.model);
}

async function loadPlatformRows(model) {
  const requestId = ++platformRequestId;
  $("platformRows").innerHTML = `<tr><td colspan="11">Yukleniyor...</td></tr>`;
  $("platformCount").textContent = "Yukleniyor";
  $("platformMetrics").innerHTML = "";
  try {
    const data = await api(`/api/platform-products?take=500&model=${encodeURIComponent(model || "")}`);
    if (requestId !== platformRequestId) return;
    const rows = data.rows || [];
    $("platformCount").textContent = `${rows.length} kayit`;
    if (!rows.length) {
      $("platformRows").innerHTML = `<tr><td colspan="11">Pazaryeri kaydi bulunamadi.</td></tr>`;
      return;
    }
    const costByBarcode = new Map((selectedModel.variants || []).map((v) => [String(v.barcode || ""), numeric(v.costPrice)]));
    const enriched = rows.map((r) => {
      const closed = r.satisaKapali === true || r.satisaKapali === 1 || String(r.satisaKapali).toLowerCase() === "true";
      const cost = costByBarcode.get(String(r.platformBarkod || "")) || 0;
      const sale = numeric(r.satisFiyati);
      return { ...r, closed, cost, sale, diff: sale - cost };
    });
    renderPlatformMetrics(enriched);
    $("platformRows").innerHTML = enriched.map((r) => {
      const status = r.closed ? "Kapali" : Number(r.durumu) === 1 ? "Aktif" : "Pasif";
      const rowClass = r.closed ? "out-stock" : r.diff < 0 ? "below-cost" : "";
      return `<tr class="${rowClass}">
        <td>${escapeHtml(r.platformTitle)}</td>
        <td>${escapeHtml(r.platformModelKodu)}</td>
        <td>${escapeHtml(r.platformStokKodu)}</td>
        <td>${escapeHtml(r.platformBarkod)}</td>
        <td>${escapeHtml(r.platformRenk)}</td>
        <td>${escapeHtml(r.platformBeden)}</td>
        <td>${formatMoney(r.cost)}</td>
        <td>${formatMoney(r.satisFiyati)}</td>
        <td>${formatMoney(r.listeFiyati)}</td>
        <td>${formatMoney(r.diff)}</td>
        <td>${escapeHtml(status)}</td>
      </tr>`;
    }).join("");
  } catch (err) {
    if (requestId !== platformRequestId) return;
    $("platformCount").textContent = "Hata";
    $("platformRows").innerHTML = `<tr><td colspan="11">${escapeHtml(err.message)}</td></tr>`;
  }
}

function renderPlatformMetrics(rows) {
  const platforms = unique(rows.map((r) => r.platformTitle).filter(Boolean));
  const prices = rows.map((r) => numeric(r.satisFiyati)).filter((x) => x > 0);
  const minPrice = prices.length ? Math.min(...prices) : 0;
  const maxPrice = prices.length ? Math.max(...prices) : 0;
  const belowCost = rows.filter((r) => r.cost > 0 && r.diff < 0).length;
  const closed = rows.filter((r) => r.closed).length;
  $("platformMetrics").innerHTML = [
    ["Platform", platforms.length],
    ["Min Satis", formatMoney(minPrice)],
    ["Max Satis", formatMoney(maxPrice)],
    ["Maliyet Alti", belowCost],
    ["Kapali", closed]
  ].map(([label, value]) => `<div><strong>${escapeHtml(value)}</strong><span>${escapeHtml(label)}</span></div>`).join("");
}

function resolveImageUrl(value) {
  const raw = (value || "").toString().trim();
  if (!raw) return "";
  if (/^https?:\/\//i.test(raw)) return raw;
  return imageBaseUrl + raw.replace(/^\/+/, "");
}

function renderImage(value, alt) {
  const url = resolveImageUrl(value);
  if (!url) return "";
  return `<img src="${escapeAttr(url)}" alt="${escapeAttr(alt || "")}" loading="lazy" onerror="this.closest('.model-thumb,.image-box')?.classList.add('image-missing'); this.remove();">`;
}

function sortModels(items, sortBy) {
  return [...items].sort((a, b) => {
    if (sortBy === "stockDesc") return numeric(b.stockTotal) - numeric(a.stockTotal);
    if (sortBy === "stockAsc") return numeric(a.stockTotal) - numeric(b.stockTotal);
    if (sortBy === "profitDesc") return numeric((b.stockValue || 0) - (b.costValue || 0)) - numeric((a.stockValue || 0) - (a.costValue || 0));
    if (sortBy === "variantDesc") return numeric(b.variantCount) - numeric(a.variantCount);
    return String(a.model).localeCompare(String(b.model));
  });
}

function summarizeModels(items) {
  return items.reduce((acc, m) => {
    acc.variantCount += Number(m.variantCount || 0);
    acc.stockTotal += Number(m.stockTotal || 0);
    acc.stockValue += Number(m.stockValue || 0);
    acc.costValue += Number(m.costValue || 0);
    return acc;
  }, { variantCount: 0, stockTotal: 0, stockValue: 0, costValue: 0 });
}

function exportCsv() {
  const rows = models.flatMap((m) => m.variants || []);
  if (!rows.length) {
    setNotice("Export icin once paneli olusturmak gerekiyor.");
    return;
  }
  const header = ["Model", "UrunKodu", "Marka", "Baslik", "Renk", "Beden", "Barkod", "Alis", "Maliyet", "Satis", "Liste", "Stok"];
  const csvRows = [header].concat(rows.map((v) => [v.model, v.productCode, v.brand, v.title, v.color, v.size, v.barcode, v.purchasePrice, v.costPrice, v.salePrice, v.listPrice, v.stock]));
  const csv = csvRows.map((row) => row.map(csvCell).join(";")).join("\r\n");
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "ecd-panel-varyantlar.csv";
  link.click();
  URL.revokeObjectURL(url);
}

async function loadStockLocations() {
  $("stockLocationNotice").textContent = "Stok gozleri yukleniyor...";
  $("stockLocationRows").innerHTML = `<tr><td colspan="12">Yukleniyor...</td></tr>`;
  const search = $("stockLocationSearch").value.trim();
  const group = $("stockLocationGroup").value;
  const take = $("stockLocationTake").value;
  try {
    const data = await api(`/api/stock-locations?take=${encodeURIComponent(take)}&group=${encodeURIComponent(group)}&search=${encodeURIComponent(search)}`);
    stockLocationRows = data.rows || [];
    renderStockLocations();
    $("stockLocationNotice").textContent = stockLocationRows.length
      ? "MULTIBRAND-001, LVT-TEKS-001, LVT-AYK-001, LVT-ÇNT-001 disindaki gozler Depo olarak gosteriliyor."
      : "Bu filtrelerle stok gozu bulunamadi.";
  } catch (err) {
    $("stockLocationCount").textContent = "Hata";
    const message = err.message === "Not found" ? "Stok servisi eski panelden cevap verdi. Sayfayi yenileyip tekrar deneyin." : err.message;
    $("stockLocationNotice").textContent = message;
    $("stockLocationRows").innerHTML = `<tr><td colspan="12">${escapeHtml(message)}</td></tr>`;
  }
}

function renderStockLocations() {
  $("stockLocationCount").textContent = `${stockLocationRows.length} kayit`;
  if (!stockLocationRows.length) {
    $("stockLocationRows").innerHTML = `<tr><td colspan="12">Kayit yok.</td></tr>`;
    return;
  }
  $("stockLocationRows").innerHTML = stockLocationRows.map((row) => {
    const stock = numeric(row.locationStock);
    const rowClass = stock <= 0 ? "out-stock" : stock <= 2 ? "low-stock" : "";
    return `<tr class="${rowClass}">
      <td><div class="table-thumb">${renderImage(row.image, row.productCode)}</div></td>
      <td>${escapeHtml(row.locationGroup)}</td>
      <td>${escapeHtml(row.shelfUnitCode)}</td>
      <td><button class="link-button stock-detail-link" type="button" data-product-code="${escapeAttr(row.productCode)}">${escapeHtml(row.productCode)}</button></td>
      <td>${escapeHtml(row.title)}</td>
      <td>${escapeHtml(row.brand)}</td>
      <td>${escapeHtml(row.color)}</td>
      <td>${escapeHtml(row.size)}</td>
      <td>${escapeHtml(row.barcode)}</td>
      <td>${escapeHtml(row.stockCode)}</td>
      <td>${escapeHtml(row.locationStock)}</td>
      <td>${escapeHtml(row.variantStock)}</td>
    </tr>`;
  }).join("");
  document.querySelectorAll(".stock-detail-link").forEach((button) => button.addEventListener("click", () => {
    $("stockDetailProductCode").value = button.dataset.productCode || "";
    loadStockDetail();
  }));
}

async function loadStockDetail() {
  const productCode = $("stockDetailProductCode").value.trim();
  if (!productCode) {
    $("stockLocationNotice").textContent = "Detay icin urun kodu yaz.";
    return;
  }
  $("stockDetailPanel").classList.remove("hidden");
  $("stockDetailTitle").textContent = `${productCode} Goz Detayi`;
  $("stockDetailCount").textContent = "Yukleniyor";
  $("stockDetailSummary").innerHTML = "";
  $("stockSizeMatrix").innerHTML = `<tbody><tr><td>Yukleniyor...</td></tr></tbody>`;
  $("stockDetailRows").innerHTML = `<tr><td colspan="12">Yukleniyor...</td></tr>`;
  try {
    const data = await api(`/api/stock-location-detail?productCode=${encodeURIComponent(productCode)}`);
    stockDetailRows = data.rows || [];
    renderStockDetail(productCode);
  } catch (err) {
    $("stockDetailCount").textContent = "Hata";
    const message = err.message === "Not found" ? "Stok detay servisi eski panelden cevap verdi. Sayfayi yenileyip tekrar deneyin." : err.message;
    $("stockSizeMatrix").innerHTML = "";
    $("stockDetailRows").innerHTML = `<tr><td colspan="12">${escapeHtml(message)}</td></tr>`;
  }
}

function renderStockDetail(productCode) {
  $("stockDetailCount").textContent = `${stockDetailRows.length} kayit`;
  if (!stockDetailRows.length) {
    $("stockDetailSummary").innerHTML = "";
    $("stockSizeMatrix").innerHTML = "";
    $("stockDetailRows").innerHTML = `<tr><td colspan="12">Bu urun kodu icin goz stogu bulunamadi.</td></tr>`;
    return;
  }
  const first = stockDetailRows[0];
  const total = stockDetailRows.reduce((sum, row) => sum + numeric(row.locationStock), 0);
  const groups = stockMatrixGroups.map((group) => {
    const sum = stockDetailRows.filter((row) => row.locationGroup === group).reduce((acc, row) => acc + numeric(row.locationStock), 0);
    return [group, sum];
  });
  $("stockDetailTitle").textContent = `${productCode} / ${first.title || ""}`;
  $("stockDetailSummary").innerHTML = [
    ["Urun Kodu", productCode],
    ["Marka", first.brand || ""],
    ["Toplam Goz Stok", total],
    ...groups
  ].map(([label, value]) => `<div><strong>${escapeHtml(value)}</strong><span>${escapeHtml(label)}</span></div>`).join("");
  renderStockSizeMatrix();
  $("stockDetailRows").innerHTML = stockDetailRows.map((row) => {
    const stock = numeric(row.locationStock);
    const rowClass = stock <= 0 ? "out-stock" : stock <= 2 ? "low-stock" : "";
    return `<tr class="${rowClass}">
      <td><div class="table-thumb">${renderImage(row.image, row.productCode)}</div></td>
      <td>${escapeHtml(row.locationGroup)}</td>
      <td>${escapeHtml(row.shelfUnitCode)}</td>
      <td>${escapeHtml(row.productCode)}</td>
      <td>${escapeHtml(row.title)}</td>
      <td>${escapeHtml(row.brand)}</td>
      <td>${escapeHtml(row.color)}</td>
      <td>${escapeHtml(row.size)}</td>
      <td>${escapeHtml(row.barcode)}</td>
      <td>${escapeHtml(row.stockCode)}</td>
      <td>${escapeHtml(row.locationStock)}</td>
      <td>${escapeHtml(row.variantStock)}</td>
    </tr>`;
  }).join("");
}

function renderStockSizeMatrix() {
  const sizes = unique(stockDetailRows.map((row) => row.size).filter(Boolean));
  const colors = unique(stockDetailRows.map((row) => row.color).filter(Boolean));
  const rows = [];
  for (const color of colors.length ? colors : [""]) {
    for (const group of stockMatrixGroups) {
      const cells = sizes.map((size) => stockDetailRows
        .filter((row) => row.locationGroup === group && String(row.color || "") === color && String(row.size || "") === size)
        .reduce((sum, row) => sum + numeric(row.locationStock), 0));
      const total = cells.reduce((sum, value) => sum + value, 0);
      if (total > 0) rows.push({ color, group, cells, total });
    }
  }
  const header = [`<th>Renk</th><th>Goz</th>`].concat(sizes.map((size) => `<th>${escapeHtml(size)}</th>`), [`<th>Toplam</th>`]).join("");
  const body = rows.map((row) => `<tr>
    <td>${escapeHtml(row.color)}</td>
    <td>${escapeHtml(row.group)}</td>
    ${row.cells.map((value) => `<td class="${value > 0 ? "matrix-hit" : ""}">${value || ""}</td>`).join("")}
    <td><strong>${row.total}</strong></td>
  </tr>`).join("");
  $("stockSizeMatrix").innerHTML = `<thead><tr>${header}</tr></thead><tbody>${body || `<tr><td colspan="${sizes.length + 3}">Beden dagilimi bulunamadi.</td></tr>`}</tbody>`;
}

function exportStockLocationsCsv() {
  if (!stockLocationRows.length) {
    setNotice("Once Stok sayfasindan stok gozlerini getirmek gerekiyor.");
    return;
  }
  const header = ["Resim", "GozGrubu", "GozAdi", "GozBarkod", "UrunKodu", "Aciklama", "Marka", "Renk", "Beden", "Barkod", "StokKodu", "GozStok", "ToplamStok"];
  const csvRows = [header].concat(stockLocationRows.map((r) => [resolveImageUrl(r.image), r.locationGroup, r.shelfUnitCode, r.shelfUnitBarcode, r.productCode, r.title, r.brand, r.color, r.size, r.barcode, r.stockCode, r.locationStock, r.variantStock]));
  const csv = csvRows.map((row) => row.map(csvCell).join(";")).join("\r\n");
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "ecs-stok-gozleri.csv";
  link.click();
  URL.revokeObjectURL(url);
}

async function loadMissingAttributes() {
  $("missingAttrNotice").textContent = "Etiket/ozellik filtresi eksikleri yukleniyor...";
  $("missingAttrRows").innerHTML = `<tr><td colspan="12">Yukleniyor...</td></tr>`;
  const keepSelectedCode = selectedFeatureProductCode();
  const search = $("missingAttrSearch").value.trim();
  const stock = $("missingAttrStock").value;
  const take = $("missingAttrTake").value;
  const feature = $("missingAttrFeature").value;
  const mode = $("missingAttrMode").value;
  const status = $("missingAttrStatus").value;
  const check = $("missingAttrCheck").value;
  const brand = selectedReportBrand();
  $("missingAttrBrand").value = brand;
  try {
    const data = await api(`/api/missing-attributes?take=${encodeURIComponent(take)}&stock=${encodeURIComponent(stock)}&feature=${encodeURIComponent(feature)}&mode=${encodeURIComponent(mode)}&status=${encodeURIComponent(status)}&check=${encodeURIComponent(check)}&brand=${encodeURIComponent(brand)}&search=${encodeURIComponent(search)}`);
    missingAttributeRows = data.rows || [];
    renderMissingAttributes();
    $("missingAttrNotice").textContent = missingAttributeRows.length
      ? missingAttributeNoticeText(status, check)
      : emptyMissingAttributeNotice(status, stock, mode, check);
    if (keepSelectedCode) {
      const refreshed = missingAttributeRows.find((row) => (row.productCode || row.missingModel || "") === keepSelectedCode);
      selectedMissingAttribute = refreshed || selectedMissingAttribute;
      renderFeatureNote({ keepText: true });
    } else {
      selectedMissingAttribute = null;
      renderFeatureNote();
    }
  } catch (err) {
    $("missingAttrCount").textContent = "Hata";
    $("missingAttrNotice").textContent = err.message;
    $("missingAttrRows").innerHTML = `<tr><td colspan="12">${escapeHtml(err.message)}</td></tr>`;
  }
}

function missingAttributeNoticeText(status, check) {
  if (check === "description") {
    if (status === "present") return "Bu listede Nebim aciklamasi olan urunler var.";
    if (status === "all") return "Bu listede Nebim aciklamasi olan ve olmayan urunler birlikte gosteriliyor.";
    return "Bu listede Nebim aciklamasi olmayan urunler var.";
  }
  if (status === "present") return "Bu listede AP_01ProductKeywords kaydi olan, yani ECS urun ozelligi bulunan urunler var.";
  if (status === "all") return "Bu listede ECS urun ozelligi olan ve olmayan urunler birlikte gosteriliyor.";
  return "Bu listede AP_01ProductKeywords kaydi olmayan, yani ECS urun ozelligi eksik urunler var.";
}

function emptyMissingAttributeNotice(status, stock, mode, check) {
  if (check === "description") return "Bu filtrelerle Nebim aciklamasi eksigi bulunamadi.";
  if (status === "missing" && stock === "in") {
    return mode === "model"
      ? "Stokta olup AP_01ProductKeywords kaydi olmayan model bulunmadi. Stoksuz veya Tum urunler secince varsa gorunur."
      : "Stokta olup AP_01ProductKeywords kaydi olmayan varyant bulunmadi. Stoksuz veya Tum urunler secince varsa gorunur.";
  }
  return "Bu filtrelerle ECS urun ozelligi eksigi bulunamadi.";
}

async function loadMissingAttributeGroups() {
  if (missingAttributeGroupsLoaded) return;
  const data = await api("/api/missing-attribute-groups");
  const groups = data.groups || [];
  $("missingAttrFeature").innerHTML = [`<option value="">Tum ozellikler</option>`]
    .concat(groups.map((g) => `<option value="${escapeAttr(g.name)}">${escapeHtml(g.name)} (${g.count})</option>`))
    .join("");
  missingAttributeGroupsLoaded = true;
}

async function loadReportBrands() {
  if (reportBrandsLoaded) return;
  const data = await api("/api/report-brands");
  reportBrands = data.brands || [];
  $("missingAttrBrandList").innerHTML = reportBrands
    .map((b) => `<option value="${escapeAttr(b.name)}" label="${escapeAttr(`${b.count} kayit`)}"></option>`)
    .join("");
  reportBrandsLoaded = true;
}

function selectedReportBrand() {
  const text = $("missingAttrBrandSearch").value.trim();
  if (!text) return "";
  const exact = reportBrands.find((b) => normalizeTurkish(b.name) === normalizeTurkish(text));
  return exact ? exact.name : text;
}

function scheduleMissingAttributesLoad() {
  clearTimeout(brandSearchTimer);
  brandSearchTimer = setTimeout(loadMissingAttributes, 450);
}

function renderMissingAttributes() {
  $("missingAttrCount").textContent = `${missingAttributeRows.length} kayit`;
  if (!missingAttributeRows.length) {
    $("missingAttrRows").innerHTML = `<tr><td colspan="12">Kayit yok.</td></tr>`;
    return;
  }
  $("missingAttrRows").innerHTML = missingAttributeRows.map((row, index) => {
    const stock = numeric(row.stock);
    const rowClass = stock <= 0 ? "out-stock" : stock <= 2 ? "low-stock" : "";
    const detailMode = $("missingAttrMode").value === "detail";
    const imageUrl = resolveImageUrl(row.image);
    return `<tr class="${rowClass}">
      <td>${imageUrl ? `<button class="image-action" type="button" data-image-url="${escapeAttr(imageUrl)}">Resim Bak</button>` : `<span class="muted-cell">Yok</span>`}</td>
      <td>${escapeHtml(row.missingFeature)}</td>
      <td>${escapeHtml(row.productCode)}</td>
      <td>${escapeHtml(row.brand)}</td>
      <td>${escapeHtml(row.title)}</td>
      <td>${escapeHtml(row.color)}</td>
      <td>${escapeHtml(detailMode ? row.size : summarizeCsvText(row.size))}</td>
      <td>${escapeHtml(detailMode ? row.barcode : `${row.barcodeCount || 0} barkod`)}</td>
      <td>${escapeHtml(row.stockCode)}</td>
      <td>${escapeHtml(row.stock)}</td>
      <td>${escapeHtml(row.photoCount)}</td>
      <td><button class="row-action" type="button" data-missing-index="${index}">Ozellik Notu Olustur</button></td>
    </tr>`;
  }).join("");
}

function renderFeatureNote(options = {}) {
  if (!selectedMissingAttribute) {
    $("featureNoteTitle").textContent = "Urun secilmedi";
    $("featureSummary").innerHTML = "";
    $("featureValue").value = "";
    $("featureNote").value = "";
    return;
  }
  const row = selectedMissingAttribute;
  const description = cleanDescription(row.description);
  const existingValue = $("featureValue").value;
  const existingNote = $("featureNote").value;
  const existingResult = $("featureWriteResult").textContent;
  $("featureNoteTitle").textContent = `${row.productCode || row.missingModel} / ${row.title || ""}`;
  $("featureSummary").innerHTML = `
    <div class="feature-image">${renderImage(row.image, row.productCode)}</div>
    <div>
      <strong>${escapeHtml(row.productCode || row.missingModel)}</strong>
      <span>${escapeHtml(row.title)}</span>
      <span>Marka: ${escapeHtml(row.brand)} - Renk: ${escapeHtml(row.color)} - Beden: ${escapeHtml(row.size)} - Eksik: ${escapeHtml(row.missingFeature)}</span>
      <span>Barkod: ${escapeHtml(row.barcode)} - Stok Kodu: ${escapeHtml(row.stockCode)}</span>
      ${row.attributes ? `<span>Mevcut Ozellikler: ${escapeHtml(row.attributes)}</span>` : ""}
      ${description ? `<span>Aciklama: ${escapeHtml(description.length > 220 ? `${description.slice(0, 220)}...` : description)}</span>` : ""}
    </div>`;
  $("featureValue").value = options.keepText ? existingValue : "";
  $("featureNote").value = options.keepText ? existingNote : "";
  $("featureWriteResult").textContent = options.keepText ? existingResult : "";
}

function openFeatureNote() {
  $("featureNotePanel").classList.remove("hidden");
  document.body.classList.add("modal-open");
}

function closeFeatureNote() {
  $("featureNotePanel").classList.add("hidden");
  document.body.classList.remove("modal-open");
}

function selectedFeatureProductCode() {
  if (!selectedMissingAttribute) return "";
  return selectedMissingAttribute.productCode || selectedMissingAttribute.missingModel || "";
}

function removeMissingCodeFromVisibleList(productCode) {
  const code = (productCode || "").toString();
  if (!code || $("missingAttrStatus").value !== "missing") return;
  const before = missingAttributeRows.length;
  missingAttributeRows = missingAttributeRows.filter((row) => (row.productCode || row.missingModel || "") !== code);
  if (missingAttributeRows.length !== before) {
    renderMissingAttributes();
    $("missingAttrNotice").textContent = `${code} guncellendi ve eksikler listesinden cikarildi.`;
  }
}

async function updateEcsFromNebim(reloadAfter = true) {
  const code = selectedFeatureProductCode();
  if (!code) {
    $("featureWriteResult").textContent = "Once bir urun sec.";
    return false;
  }
  $("featureWriteResult").textContent = "Nebimden ECS guncelleme yapiliyor...";
  try {
    const result = await api("/api/ecs-update-from-nebim", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({ productCode: code })
    });
    $("featureWriteResult").textContent = result.message || "ECS Nebimden guncellendi.";
    if (reloadAfter) {
      await loadMissingAttributes();
      removeMissingCodeFromVisibleList(code);
      closeFeatureNote();
    }
    return true;
  } catch (err) {
    $("featureWriteResult").textContent = `ECS guncellenemedi: ${err.message}`;
    return false;
  }
}

async function askEcsUpdateAfterNebim(successMessage) {
  $("featureWriteResult").textContent = successMessage;
  const shouldUpdate = window.confirm("Nebim'e yazildi. Simdi Nebimden ECS guncelleme yapilsin mi?");
  let updated = false;
  if (shouldUpdate) {
    updated = await updateEcsFromNebim(false);
  }
  await loadMissingAttributes();
  if (updated) {
    removeMissingCodeFromVisibleList(selectedFeatureProductCode());
    closeFeatureNote();
  }
}

function summarizeCsvText(value) {
  const items = unique(String(value || "").split(",").map((x) => x.trim()).filter(Boolean));
  if (items.length <= 4) return items.join(", ");
  return `${items.slice(0, 4).join(", ")} +${items.length - 4}`;
}

function suggestFeatureValue(row) {
  const feature = normalizeTurkish(row.missingFeature);
  const title = `${row.title || ""} ${row.productCode || ""}`.toLowerCase();
  if (feature.includes("renk")) return row.color || "";
  if (feature.includes("marka")) return row.brand || "";
  if (feature.includes("cinsiyet")) {
    if (title.includes("kadın") || title.includes("kadin")) return "Kadın / Kız";
    if (title.includes("erkek")) return "Erkek";
    if (title.includes("çocuk") || title.includes("cocuk") || title.includes("bebek")) return "Çocuk";
  }
  return "";
}

function buildFeatureDraft(row, value) {
  return [
    `Urun Kodu: ${row.productCode || row.missingModel}`,
    `Eksik Ozellik: ${row.missingFeature || ""}`,
    `Onerilen Deger: ${value || ""}`,
    `Marka: ${row.brand || ""}`,
    `Baslik: ${row.title || ""}`,
    `Mevcut Ozellikler: ${row.attributes || ""}`,
    `Aciklama: ${cleanDescription(row.description) || ""}`,
    `Renk: ${row.color || ""}`,
    `Beden: ${row.size || ""}`,
    `Barkod: ${row.barcode || ""}`,
    `Stok Kodu: ${row.stockCode || ""}`,
    `Resim: ${resolveImageUrl(row.image)}`
  ].join("\n");
}

function generateFeature() {
  if (!selectedMissingAttribute) return;
  const value = suggestFeatureValue(selectedMissingAttribute);
  $("featureValue").value = value;
  $("featureNote").value = buildFeatureDraft(selectedMissingAttribute, value);
}

function webSearchFeature() {
  if (!selectedMissingAttribute) return;
  const row = selectedMissingAttribute;
  const value = $("featureValue").value.trim() || suggestFeatureValue(row);
  $("featureValue").value = value;
  $("featureNote").value = buildFeatureDraft(row, value);
  const query = [
    row.brand,
    row.title,
    row.productCode,
    row.color,
    row.missingFeature,
    row.barcode,
    cleanDescription(row.description).slice(0, 120)
  ].filter(Boolean).join(" ");
  window.open(`https://www.google.com/search?q=${encodeURIComponent(query)}`, "_blank", "noreferrer");
}

async function writeFeatureToNebim() {
  if (!selectedMissingAttribute) return;
  const row = selectedMissingAttribute;
  if ($("missingAttrCheck").value === "description") {
    const description = $("featureNote").value.trim();
    if (!description) {
      $("featureWriteResult").textContent = "Once Not / Web Arama Bilgisi alanina aciklama yaz.";
      return;
    }
    $("featureWriteResult").textContent = "Aciklama yaziliyor...";
    try {
      const result = await api("/api/product-description", {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify({
          productId: row.productId,
          productCode: row.productCode || row.missingModel,
          description
        })
      });
      await askEcsUpdateAfterNebim(result.message || "Nebim aciklama/not yazildi.");
    } catch (err) {
      $("featureWriteResult").textContent = err.message;
    }
    return;
  }
  const value = $("featureValue").value.trim();
  if (!value) {
    $("featureWriteResult").textContent = "Once ozellik degeri gir.";
    return;
  }
  $("featureWriteResult").textContent = "Yaziliyor...";
  try {
    const result = await api("/api/product-attribute", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({
        productId: row.productId,
        productCode: row.productCode || row.missingModel,
        feature: row.missingFeature,
        value,
        note: $("featureNote").value.trim() || buildFeatureDraft(row, value)
      })
    });
    await askEcsUpdateAfterNebim(result.message || "Ozellik yazildi.");
  } catch (err) {
    $("featureWriteResult").textContent = err.message;
  }
}

function showPage(page) {
  const products = page === "products";
  const stock = page === "stock";
  const reports = page === "reports";
  $("pageProducts").classList.toggle("active", products);
  $("pageStock").classList.toggle("active", stock);
  $("pageReports").classList.toggle("active", reports);
  $("productWorkspace").classList.toggle("hidden", !products);
  document.querySelectorAll(".tab-button").forEach((btn) => btn.classList.toggle("active", btn.dataset.page === page));
  if (stock && !stockLocationRows.length) {
    loadStockLocations();
  }
  if (reports) {
    loadMissingAttributeGroups().catch((err) => $("missingAttrNotice").textContent = err.message);
    loadReportBrands().catch((err) => $("missingAttrNotice").textContent = err.message);
    if (!missingAttributeRows.length) loadMissingAttributes();
  }
}

function normalizeTurkish(value) {
  return (value || "").toString().toLocaleLowerCase("tr-TR");
}

function exportMissingAttributesCsv() {
  if (!missingAttributeRows.length) {
    setNotice("Once ozellik eksigi listesini getirmek gerekiyor.");
    return;
  }
  const header = ["EksikOzellik", "UrunKodu", "Marka", "Baslik", "Renk", "Beden", "Barkod", "StokKodu", "Stok", "Foto", "Resim"];
  const csvRows = [header].concat(missingAttributeRows.map((r) => [r.missingFeature, r.productCode, r.brand, r.title, r.color, r.size, r.barcode, r.stockCode, r.stock, r.photoCount, resolveImageUrl(r.image)]));
  const csv = csvRows.map((row) => row.map(csvCell).join(";")).join("\r\n");
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "ecd-panel-ozellik-eksikleri.csv";
  link.click();
  URL.revokeObjectURL(url);
}

function clearFilters() {
  $("search").value = "";
  $("stockFilter").value = "all";
  $("sortBy").value = "model";
  renderModels();
  renderDetail();
}

function csvCell(value) {
  const text = (value ?? "").toString().replace(/"/g, '""');
  return `"${text}"`;
}

function numeric(value) {
  const n = Number(String(value ?? "0").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}

function formatMoney(value) {
  if (value === null || value === undefined || value === "") return "";
  return numeric(value).toLocaleString("tr-TR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatCompactMoney(value) {
  return numeric(value).toLocaleString("tr-TR", { maximumFractionDigits: 0 });
}

function formatPercent(value) {
  if (!Number.isFinite(value)) return "0";
  return (value * 100).toLocaleString("tr-TR", { maximumFractionDigits: 1 });
}

function cleanDescription(value) {
  const div = document.createElement("div");
  div.innerHTML = value || "";
  return (div.textContent || div.innerText || "")
    .replace(/\bFormAciklamaGoster\b/gi, " ")
    .replace(/^\s*c\d+\s*/i, "")
    .replace(/\s+/g, " ")
    .trim();
}

function firstValue(items, key) {
  const hit = items.find((item) => item[key]);
  return hit ? hit[key] : "";
}

function unique(values) {
  return [...new Set(values.map((x) => String(x)))].sort((a, b) => a.localeCompare(b));
}

function escapeHtml(value) {
  return (value ?? "").toString().replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" }[ch]));
}

function escapeAttr(value) {
  return escapeHtml(value).replace(/`/g, "&#096;");
}

$("refresh").addEventListener("click", refreshStatus);
$("database").addEventListener("change", loadSchema);
$("loadPreview").addEventListener("click", loadSchema);
$("buildPanel").addEventListener("click", buildPanel);
$("demoData").addEventListener("click", loadDemo);
$("liveProducts").addEventListener("click", loadLiveProducts);
$("serverSearch").addEventListener("click", loadLiveProducts);
$("clearFilters").addEventListener("click", clearFilters);
$("exportCsv").addEventListener("click", exportCsv);
$("loadMissingAttrs").addEventListener("click", loadMissingAttributes);
$("exportMissingAttrs").addEventListener("click", exportMissingAttributesCsv);
$("loadStockLocations").addEventListener("click", loadStockLocations);
$("exportStockLocations").addEventListener("click", exportStockLocationsCsv);
$("loadStockDetail").addEventListener("click", loadStockDetail);
$("generateFeature").addEventListener("click", generateFeature);
$("webSearchFeature").addEventListener("click", webSearchFeature);
$("writeFeature").addEventListener("click", writeFeatureToNebim);
$("updateEcsFromNebim").addEventListener("click", updateEcsFromNebim);
document.querySelectorAll(".tab-button").forEach((btn) => btn.addEventListener("click", () => showPage(btn.dataset.page)));
$("search").addEventListener("input", renderModels);
$("search").addEventListener("keydown", (event) => {
  if (event.key === "Enter") loadLiveProducts();
});
$("stockFilter").addEventListener("change", () => { renderModels(); renderDetail(); });
$("sortBy").addEventListener("change", () => { renderModels(); renderDetail(); });
$("missingAttrSearch").addEventListener("keydown", (event) => {
  if (event.key === "Enter") loadMissingAttributes();
});
$("stockLocationSearch").addEventListener("keydown", (event) => {
  if (event.key === "Enter") loadStockLocations();
});
$("stockDetailProductCode").addEventListener("keydown", (event) => {
  if (event.key === "Enter") loadStockDetail();
});
$("stockLocationGroup").addEventListener("change", loadStockLocations);
$("stockLocationTake").addEventListener("change", loadStockLocations);
$("missingAttrFeature").addEventListener("change", loadMissingAttributes);
$("missingAttrBrandSearch").addEventListener("input", scheduleMissingAttributesLoad);
$("missingAttrBrandSearch").addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    loadMissingAttributes();
  }
});
$("missingAttrCheck").addEventListener("change", loadMissingAttributes);
$("missingAttrStatus").addEventListener("change", loadMissingAttributes);
$("missingAttrMode").addEventListener("change", loadMissingAttributes);
$("missingAttrStock").addEventListener("change", loadMissingAttributes);
$("missingAttrTake").addEventListener("change", loadMissingAttributes);
$("missingAttrRows").addEventListener("click", (event) => {
  const imageButton = event.target.closest(".image-action[data-image-url]");
  if (imageButton) {
    event.stopPropagation();
    window.open(imageButton.dataset.imageUrl, "_blank", "noopener,noreferrer");
    return;
  }

  const featureButton = event.target.closest(".row-action[data-missing-index]");
  if (featureButton) {
    event.stopPropagation();
    const index = Number(featureButton.dataset.missingIndex);
    selectedMissingAttribute = missingAttributeRows[index];
    if (!selectedMissingAttribute) {
      $("missingAttrNotice").textContent = "Urun secilemedi. Listeyi yenileyip tekrar deneyin.";
      return;
    }
    renderFeatureNote();
    openFeatureNote();
  }
});
$("closeFeatureNote").addEventListener("click", closeFeatureNote);
$("featureNotePanel").addEventListener("click", (event) => {
  if (event.target === $("featureNotePanel")) closeFeatureNote();
});
refreshStatus().then(loadSchema).catch((err) => setNotice(err.message));
