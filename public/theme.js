// Set light or dark before the page draws, so it never flashes the wrong colors.
try { document.documentElement.setAttribute("data-theme", localStorage.getItem("sp-theme") || "light"); } catch (e) { document.documentElement.setAttribute("data-theme", "light"); }
