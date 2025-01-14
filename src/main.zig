const std = @import("std");
const termsize = @import("termsize");
const ChildProcess = std.process.Child;
const meta = std.meta;
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
        .allocator = allocator,
        .argv = &.{ "stty", "raw", "-echo", "min", "0", "time", "1", "-F", "/dev/tty" },
    });
}
/// Resets the terminal and turns echo on
fn unsetRawYesEchoBlocking() !void {
    _ = try ChildProcess.run(.{
        .allocator = allocator,
        .argv = &.{ "stty", "-raw", "echo", "icanon", "-F", "/dev/tty" },
    });
}

fn clear() !void {
    _ = try ChildProcess.run(.{
        .allocator = allocator,
        .argv = &.{ "clear"},
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

const direction = struct {
    right: @Vector(2, i2) = .{ 1, 0 }, 
    up: @Vector(2, i2) = .{ -1, 0 }, 
    down: @Vector(2, i2) = .{ 0, 1 }, 
    left: @Vector(2, i2) = .{ 0, -1 } 
    };
const dir = direction{};
const Scale = struct {
    pos: @Vector(2, isize),
    next: ?*Scale = null,
    moved: @Vector(2, i2) = .{ 0, 1 },

    fn update(self: *@This()) void {
        const next: ?*Scale = self.next orelse null;
        if(next) |scale| {
            self.pos = self.pos+scale.moved;
        }
        else self.pos = self.pos+self.moved;
    }
};

/// Linked list data structure, links forward to head
const Body = struct {
    head: *Scale,
    tail: *Scale,

    fn posIsHead(self: *@This(), point: @Vector(2, usize)) bool {
        return (self.head.pos[0] == point[0]) and (self.head.pos[1] == point[1]);
    }

    fn at(self: *@This()) !ArrayList(@Vector(2, isize)) {
        var snakeAt = ArrayList(@Vector(2, isize)).init(allocator);
        const head = self.head;
        try snakeAt.append(head.pos);
        var next = head.next;
        while (next) |scale| {
            try snakeAt.append(scale.pos);
            next = scale.next;
        }
        return snakeAt;
    }

    ///Extends the snake at the tail
    fn grow(self: *@This()) !void {
        const newTail = try allocator.create(Scale);

        newTail.* = Scale{
            .pos = @as(@Vector(2, isize), self.tail.pos) - @as(@Vector(2, isize), self.tail.moved),
            .moved = self.tail.moved,
            .next = null,
        };
        
        if (self.head.next == null) {
            self.tail = newTail;
            self.head.next = self.tail;
        } else {
            var temp = self.tail;
            temp.next = newTail;
            self.tail = newTail;
        }
    }
};

const Snake = struct {
    speed: f16 = 100,
    body: Body,
    at: ArrayList(@Vector(2, isize)) = ArrayList(@Vector(2, isize)).init(allocator),

    fn len(self: *@This()) usize {
        return self.at.items.len;
    }
    fn find(self: *@This()) !void {
        self.at = try self.body.at();
    }
    fn eat(self: *@This()) !void {
        try self.body.grow();
    }

    fn move(self: *@This()) void {
        const head = self.body.head;
        head.update();
        var next: ?*Scale = head.next orelse null;

        if(next) |scale|{
            scale.moved = head.moved;
        }

        while (next) |scale| {
            next = scale.next orelse null;
            scale.update();
            if (next) |nextScale| {
            nextScale.moved = scale.moved;
            }
        }
    }

    fn containedIn(self: *@This(), point: @Vector(2, usize)) bool {
        for (0..self.at.items.len) |i| {
            const snake = self.at.items[i];
            if ((snake[0] == point[0]) and (snake[1] == point[1])) {
                return true;
            }
        }
        return false;
    }

    fn input(self: *@This(), key: u8) void {
        return switch (key) {
            'w' => {
                self.body.head.moved = dir.up;
            },
            'a' => {
                self.body.head.moved = dir.left;
            },
            's' => {
                self.body.head.moved = dir.right;
            },
            'd' => {
                self.body.head.moved = dir.down;
            },
            else => {},
        };
    }
};

const Game = struct {
    list: ArrayList(u8) = ArrayList(u8).init(allocator),
    rows: u16,
    cols: u16,

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

    fn drawFrame(self: *@This(), snake: *Snake) !void {
        try snake.find();
        for (0..self.rows) |y| {
            for (0..self.cols) |x| {
                const pos: @Vector(2, usize) = .{ y, x };
                if (snake.containedIn(pos)) {
                    if (snake.body.posIsHead(pos)) {
                        try self.setColor(MAGENTA);
                    } else {
                        try self.setColor(GREEN);
                    }
                    try self.append('#');
                } else {
                    try self.setColor(BLUE);
                    try self.append('.');
                }
            }
        }
    }

    fn fill(self: *@This()) !void {
        try self.appendSlice(cursor_hide);
        try self.setColor(BLUE);
        // const center = (self.cols / 2) + (self.rows / 2) * self.cols;
        for (0..self.rows) |y| {
            for (0..self.cols) |x| {
                const index = y * self.cols + x;
                // i++;
                if (index == 0) {
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
                    try self.append('.');
                }
            }
        }
    }
};

pub fn main() !void {
    const termsz = try termsize.termSize(std.io.getStdOut());
    const rows = termsz.?.height;
    const cols = termsz.?.width;
    // const center = (cols/2) + (rows/2)*cols;
    const startX = cols / 2;
    const startY = rows / 2;
    const head = try allocator.create(Scale);
    head.* = Scale{
        .pos = .{ startY, startX },
    };

    var snake = Snake{
        .body = .{ .head = head, .tail = head },
    };

    // snake.createHead(rows/2, cols/2);
    var terminal = Game{ .rows = rows, .cols = cols };
    defer terminal.done();

    try setRawNoEchoNonBlocking();
    defer unsetRawYesEchoBlocking() catch {
        print("Warning: Failed to restore terminal settings\n", .{});
    };

    try terminal.fill();
    terminal.display();
    

    //TESTING

    // try snake.find();
    try snake.eat();
    // var ptrTail = snake.body.tail;
    // var ptrHead = snake.body.head;
    // print("head: {any} \ntail: {any}\n\n", .{ ptrHead, ptrTail });

    // snake.input('w');
    // snake.move();
    try snake.eat();
    // ptrTail = snake.body.tail;
    // ptrHead = snake.body.head;
    // print("head: {any} \ntail: {any}\n", .{ ptrHead, ptrTail });

    // GAME LOOP
    const nPs = 1_000_000_000;
    const FPS = 60;
    sleep(3*nPs);
    var i: u16 = 0;
    while (true) {
        // try snake.eat();
        snake.move();
        try terminal.clear();
        try clear();
        // terminal.display();
        try terminal.drawFrame(&snake);
        terminal.display();
        i += 1;
        // print("{d}", .{i});
        const keyDown = try getChar();
        if (keyDown) |char| {
            snake.input(char);
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
