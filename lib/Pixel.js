.pragma library

// Whole device pixels. Everything the pill and its join to the card are made of
// (left edge, width, radii, heights) is snapped with this ONE function, so the
// left and the right side start from the same numbers and are exact mirror images,
// at any display scale (1, 1.25, 1.5, 2...) and for any fractional pill position.

function snap(v, dpr) {
  var d = dpr > 0 ? dpr : 1
  return Math.round(v * d) / d
}
