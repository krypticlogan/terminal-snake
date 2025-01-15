const std = @import("std");
const termsize = @import("termsize");
const ChildProcess = std.process.Child;
const meta = std.meta;
const print = std.debug.print;

const esc = "\x1B";
const csi = esc ++ "[";

const cursor_show = csi ++ "?25h"; //h=high
const cursor_hide = csi ++ "?25l"; //l=low
const cursor_home = csi ++ "1;1H"; //1,1

const color_fg = "38;5;";
const color_bg = "48;5;";

const clear_screen = "\x1b[2J\x1b[H";

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
        .argv = &.{"clear"},
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

const direction = struct { right: @Vector(2, i2) = .{ 1, 0 }, up: @Vector(2, i2) = .{ -1, 0 }, down: @Vector(2, i2) = .{ 0, 1 }, left: @Vector(2, i2) = .{ 0, -1 } };
const dir = direction{};

const Scale = struct {
    pos: @Vector(2, isize),
    next: ?*Scale = null,
    moved: ?@Vector(2, i2) = null,

    fn update(self: *@This()) void {
        const next: ?*Scale = self.next orelse null;
        if (next) |scale| {
            self.pos = scale.pos;
        } else self.pos = self.pos + self.moved.?;
    }
};

/// Linked list data structure, links forward to head
const Body = struct {
    head: *Scale,
    tail: *Scale,

    fn posIsHead(self: *@This(), point: @Vector(2, usize)) bool {
        return (self.tail.pos[0] == point[0]) and (self.tail.pos[1] == point[1]);
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
            .pos = @as(@Vector(2, isize), self.tail.pos),
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
    alive: bool = true,
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

        if (next) |scale| {
            scale.moved = head.moved;
        }

        while (next) |scale| {
            next = scale.next orelse null;
            if (next) |nextScale| {
                nextScale.moved = scale.moved;
            }
            scale.update();
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

    // fn checkOverlapping(self: *@This()) void {
    //     var i: u16 = 0;
    //     for (self.at.items) |pos| {
    //         i+=1;
    //         if (pos)
    //     }
    // }
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

const Apple = struct {
    pos: ?@Vector(2, usize) = null,

    fn place(self: *@This(), rows: u16, cols: u16, snake: *Snake) !void {
        //Random number gen
        var prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });
        var rand = prng.random();
        if (self.pos == null) {
            self.pos = .{ rand.intRangeAtMost(u16, 0, rows), rand.intRangeAtMost(u16, 0, cols) };
        }
        while (snake.containedIn(self.pos.?)) {
            self.pos.?[0] = rand.intRangeAtMost(u16, 0, rows);
            self.pos.?[1] = rand.intRangeAtMost(u16, 0, cols);
        }
    }

    fn containedIn(self: *@This(), point: @Vector(2, usize)) bool {
        return (self.pos.?[0] == point[0]) and (self.pos.?[1] == point[1]);
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

    fn drawFrame(self: *@This(), snake: *Snake, apple: *Apple) !void {
        try snake.find();
        //TODO: Kill when overlapping
        // snake.checkOverlapping();
        for (0..self.rows) |y| {
            for (0..self.cols) |x| {
                const pos: @Vector(2, usize) = .{ y, x };
                if (snake.containedIn(pos)) { //SNAKE LOGIC
                    const snakeHead = snake.body.tail.pos;
                    if (snakeHead[0] < 0 or snakeHead[0] > self.rows or snakeHead[1] < 0 or snakeHead[1] > self.cols) {
                        try self.clear();
                        try self.appendSlice("YOU DIED");
                        snake.alive = false;
                        break;
                    }
                    if (snake.body.posIsHead(pos)) {
                        try self.setColor(MAGENTA);
                    } else {
                        try self.setColor(GREEN);
                    }
                    try self.append('#');
                    if (apple.containedIn(pos)) {
                        try snake.eat();
                        try apple.place(self.rows, self.cols, snake);
                    }
                }
                //
                else if (apple.containedIn(pos)) {
                    try self.setColor(RED);
                    try self.append('@');
                } else {
                    try self.append(' ');
                }
            }
        }
    }

    fn fill(self: *@This(), seconds: u8) !void {
        try self.appendSlice(cursor_hide);
        try self.setColor(BLUE);
        const center = (self.cols / 2) + (self.rows / 2) * self.cols;
        for (0..self.rows) |y| {
            for (0..self.cols) |x| {
                const index = y * self.cols + x;
                // i++;
                if (index == center) {
                    try self.setColor(RED);
                    try self.append(seconds);
                    try self.setColor(BLUE);
                } else if (x == self.cols - 1) {
                    try self.append('<');
                } else if (y == 0) {
                    try self.append('v');
                } else if (y == self.rows - 1) {
                    try self.append('^');
                } else if (x == 0) {
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
    const startX = cols / 2;
    const startY = rows / 2;
    const head = try allocator.create(Scale);

    head.* = Scale{ .pos = .{ startY, startX }, .moved = .{ 0, 1 } };

    var snake = Snake{
        .body = .{ .head = head, .tail = head },
    };
    var apple = Apple{};
    try apple.place(rows, cols, &snake);
    // snake.createHead(rows/2, cols/2);
    var terminal = Game{ .rows = rows, .cols = cols };
    defer terminal.done();

    try setRawNoEchoNonBlocking();
    defer unsetRawYesEchoBlocking() catch {
        print("Warning: Failed to restore terminal settings\n", .{});
    };

    try snake.find();
    // GAME LOOP
    const nPs = 1_000_000_000;
    const FPS = 60;

    while (true and snake.alive) {
        snake.move();
        try terminal.clear();
        try clear();
        try terminal.drawFrame(&snake, &apple);
        terminal.display();
        const keyDown = try getChar();
        if (keyDown) |char| {
            snake.input(char);
            if (char == QUIT) {
                print("exited", .{});
                break;
            } // quit on 'q'
        }
        sleep(nPs / FPS);
    }
}
