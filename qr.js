/**
 * @schema 2.11
 * @input modules: number = 25
 * @input color: color = #0C1220
 * @input bg: color = #FFFFFF
 */
const m = Math.max(21, Math.floor(pencil.input.modules));
const cell = pencil.width / m;
const ink = pencil.input.color;
const nodes = [];
const inFinder = (x, y) => (x < 8 && y < 8) || (x >= m - 8 && y < 8) || (x < 8 && y >= m - 8);
for (let y = 0; y < m; y++) {
  for (let x = 0; x < m; x++) {
    if (inFinder(x, y)) continue;
    if (Math.random() < 0.46) {
      nodes.push({ type: "rectangle", name: "Module", x: x * cell, y: y * cell, width: cell, height: cell, fill: ink });
    }
  }
}
const finder = (fx, fy) => {
  nodes.push({ type: "rectangle", name: "Finder Outer", x: fx * cell, y: fy * cell, width: 7 * cell, height: 7 * cell, fill: ink });
  nodes.push({ type: "rectangle", name: "Finder Gap", x: (fx + 1) * cell, y: (fy + 1) * cell, width: 5 * cell, height: 5 * cell, fill: pencil.input.bg });
  nodes.push({ type: "rectangle", name: "Finder Core", x: (fx + 2) * cell, y: (fy + 2) * cell, width: 3 * cell, height: 3 * cell, fill: ink });
};
finder(0, 0);
finder(m - 7, 0);
finder(0, m - 7);
return nodes;
