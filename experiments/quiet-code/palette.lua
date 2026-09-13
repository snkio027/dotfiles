-- Experimental visual values only; production C4.4 remains unchanged.
local M = {}

function M.apply(p)
	p.code = {
		variable = "#CFD3DD",
		parameter = "#CFD3DD",
		member = "#BAC3D2",
		namespace = "#A0AABC",
		label = "#A0AABC",
		keyword = "#B5A2D9",
		keyword_function = "#B5A2D9",
		meta = "#B5A2D9",
		callable = "#DDB97B",
		type = "#7DBDB4",
		builtin = "#93B7B1",
		lifetime = "#93B7B1",
		string = "#A9B99A",
		number = "#D2AB8D",
		constant = "#D2AB8D",
		operator = "#A3ACBC",
		punctuation = "#8E98AA",
		comment = "#858D9E",
		doc = "#A2ABB9",
	}
	p.ui.normal_bg = "#1B1D24"
	p.ui.normal_fg = p.code.variable
	p.ui.focus = "#DDB97B"
	p.ui.selection_bg = "#303848"
	p.ui.selection_fg = "#E4E8F0"
	p.ui.stopped_bg = "#22252D"
	return p
end

return M
