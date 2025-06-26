const std = @import("std");
const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub fn main() !void {
    c.InitWindow(1280, 720, "Arena");
    defer c.CloseWindow();

    while (!c.WindowShouldClose()) {
        var mousePosition = c.Vector2{ .x = 0, .y = 0 };
        if (c.GetTouchPointCount() > 0) {
            mousePosition = c.GetTouchPosition(0);
        }
        c.BeginDrawing();
        defer c.EndDrawing();

        c.ClearBackground(c.SKYBLUE);
        c.DrawText(c.TextFormat("TouchPosition {x=%f, y=%f}", mousePosition.x, mousePosition.y), 10, 30, 20, c.RED);
        c.DrawCircleV(mousePosition, 20, c.RED);
    }
}

test "simple test" {
    try std.testing.expectEqual(1, 1);
}
