const std = @import("std");
const termsize = @import("termsize");
const ChildProcess = std.process.Child;
// const stdout = @import("stdout");
const print = std.debug.print;

const esc = "\x1B";
const csi = esc ++ "[";

const cursor_show = csi ++ "?25h"; //h=high
const cursor_hide = csi ++ "?25l"; //l=low
const cursor_home = csi ++ "1;1H"; //1,1

const color_fg = "38;5;";
const color_bg = "48;5;";
// const color_fg_def = csi ++ color_fg ++ "15m"; // white
// const color_bg_def = csi ++ color_bg ++ "0m"; // black
// const color_def = color_bg_def ++ color_fg_def;
const clear_screen = "\x1b[2J\x1b[H";
const screen_clear = csi ++ "2J";
const screen_buf_on = csi ++ "?1049h"; //h=high
const screen_buf_off = csi ++ "?1049l"; //l=low

const nl = "\n";

const RED = csi ++ "31m";
const GREEN = csi ++ "32m";
const YELLOW = csi ++ "33m";
const BLUE = csi ++ "34m";
const MAGENTA = csi ++ "35m";
const CYAN = csi ++ "36m";
const RESET = csi ++ "0m";

// const TermSz = struct { height: usize, width: usize };
const allocator = std.heap.page_allocator;
const ArrayList = std.ArrayList;
const sleep = std.time.sleep;

const PAUSE = 'p';
const QUIT = 'q';

/// Sets the terminal to raw mode and turns off echo and canonical mode
/// Dont for get to unsetRawYesEcho
fn setRawNoEchoNonBlocking() !void {
    _ = try ChildProcess.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "stty", "raw", "-echo", "min", "0", "time", "1", "-F", "/dev/tty" },
    });
}
/// Resets the terminal and turns echo on
fn unsetRawYesEchoBlocking() !void {
    _ = try ChildProcess.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "stty", "-raw", "echo", "icanon", "-F", "/dev/tty" },
    });
}

/// Waits to recieve a keyboard event from std out
pub fn getChar() !?u8 {
    const stdin = std.io.getStdIn();
    var buf: [1]u8 = undefined;

    const bytes_read = stdin.read(&buf) catch |err| switch (err) {
        error.ConnectionTimedOut => return null,
        else => return err,
    };

    if (bytes_read == 0) return null; // Non-blocking read returned no data
    return buf[0];
}

const direction = enum {
    up,
    down,
    left,
    right,

    fn isUp(self: *@This()) bool {
        return self == direction.up;
    }
};

const Snake = struct {
    x: u16,
    y: u16,
    speed: f16 = 100,

    fn update(key: u8) direction {
        return switch (key) {
            'w' => {
                direction.up;
            },
            else => {},
        };
    }
};

const List = struct {
    list: ArrayList(u8) = ArrayList(u8).init(allocator),
    rows: u16,
    cols: u16,
    snake: Snake,

    fn len(self: *@This()) usize {
        return self.list.items.len;
    }

    fn items(self: *@This()) []u8 {
        return self.list.items;
    }
    fn append(self: *@This(), data: u8) !void {
        try self.list.append(data);
    }

    fn appendSlice(self: *@This(), data: []const u8) !void {
        try self.list.appendSlice(data);
    }

    fn get(self: *@This(), index: usize) ?[]u8 {
        if (index >= self.len()) {
            return null;
        }
        return self.list.items[index .. index + 1];
    }

    fn clear(self: *@This()) !void {
        self.list.clearAndFree();
        try self.appendSlice(clear_screen);
    }

    //self.defer done
    fn done(self: *@This()) void {
        self.list.deinit();
    }

    fn setColor(self: *@This(), color: *const [5:0]u8) !void {
        try self.appendSlice(color);
    }

    fn display(self: *@This()) void {
        print("\n{s}", .{self.items()});
    }

    fn fill(self: *@This(), playerCoord: usize) !void {
        try self.setColor(BLUE);
        // const center = (self.cols / 2) + (self.rows / 2) * self.cols;
        for (0..self.rows) |y| {
            for (0..self.cols) |x| {
                const index = y * self.cols + x;
                // i++;
                if (index == playerCoord) {
                    try self.setColor(RED);
                    try self.append('*');
                    try self.setColor(BLUE);
                } else if (x == self.cols - 1) {
                    try self.append('<');
                } else if (y == 0) {
                    try self.append('v');
                } else if (y == self.rows - 1) {
                    try self.append('^');
                } else if (x == 0) {
                    // printf("x is 0");
                    try self.append('>');
                } else {
                    try self.append('#');
                }
            }
        }
    }
};

pub fn main() !void {
    const termsz = try termsize.termSize(std.io.getStdOut());
    const rows = termsz.?.height;
    const cols = termsz.?.width;

    const snake = Snake{ .x = 0, .y = 0 };
    var terminal = List{ .rows = rows, .cols = cols, .snake = snake };
    defer terminal.done();

    try setRawNoEchoNonBlocking();
    defer unsetRawYesEchoBlocking() catch {
        print("Warning: Failed to restore terminal settings\n", .{});
    };
    
    const nPs = 1_000_000_000;
    const FPS = 60;
    var i: u16 = 0;
    while (true) {
        try terminal.clear();
        terminal.display();
        try terminal.fill(i);
        terminal.display();
        i += 1;
        // print("{d}", .{i});
        const keyDown = try getChar();
        if (keyDown) |char| {
            // if (char == UP) {print("up",.{}); break;}
            // if (char == DOWN) {print("down",.{}); break;}
            // if (char == LEFT) {print("left",.{}); break;}
            // if (char == RIGHT) {print("right",.{}); break;}
            // if (char == SPEED?) {print("speeeed",.{}); break;}
            // if (char == PAUSE) {print("paused",.{});}
            if (char == QUIT) {
                print("exited", .{});
                break;
            } // quit on 'q'
        }
        sleep(nPs / FPS);
    }
}
