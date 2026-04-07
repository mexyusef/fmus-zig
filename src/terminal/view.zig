const state_mod = @import("state.zig");
const cell_mod = @import("cell.zig");
const action_mod = @import("action.zig");

pub const ScreenView = struct {
    state: *const state_mod.State,

    pub fn init(state: *const state_mod.State) ScreenView {
        return .{ .state = state };
    }

    pub fn rows(self: ScreenView) usize {
        return self.state.rowCount();
    }

    pub fn cols(self: ScreenView) usize {
        return self.state.colCount();
    }

    pub fn cursorRow(self: ScreenView) usize {
        return self.state.cursor.row;
    }

    pub fn cursorCol(self: ScreenView) usize {
        return self.state.cursor.col;
    }

    pub fn cursorVisible(self: ScreenView) bool {
        return self.state.cursor.visible and self.state.viewport_offset == 0;
    }

    pub fn cursorShape(self: ScreenView) action_mod.CursorShape {
        return self.state.cursor_shape;
    }

    pub fn cell(self: ScreenView, row: usize, col: usize) cell_mod.Cell {
        return self.state.cellAtView(row, col);
    }

    pub fn rowWrapped(self: ScreenView, row: usize) bool {
        return self.state.rowWrappedAtView(row);
    }

    pub fn directCells(self: ScreenView) ?[]const cell_mod.Cell {
        return self.state.screenCellsDirect();
    }
};
