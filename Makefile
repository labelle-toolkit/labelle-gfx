.PHONY: all build test clean help run-01 run-02 run-03 run-04 run-05 run-06 run-07 run-08 run-basic-sprite run-animation run-sprite-atlas run-camera run-ecs-rendering run-effects run-with-fixtures run-nested-animations run-all

all: build

build:
	zig build

test:
	zig build test

clean:
	rm -rf zig-out .zig-cache

run-01:
	zig build run-01_basic_sprite

run-02:
	zig build run-02_animation

run-03:
	zig build run-03_sprite_atlas

run-04:
	zig build run-04_camera

run-05:
	zig build run-05_ecs_rendering

run-06:
	zig build run-06_effects

run-07:
	zig build run-07_with_fixtures

run-08:
	zig build run-08_nested_animations

run-basic-sprite: run-01
run-animation: run-02
run-sprite-atlas: run-03
run-camera: run-04
run-ecs-rendering: run-05
run-effects: run-06
run-with-fixtures: run-07
run-nested-animations: run-08

run-all: run-01 run-02 run-03 run-04 run-05 run-06 run-07 run-08

help:
	@echo "raylib-ecs-gfx Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make build              - Build the library"
	@echo "  make test               - Run tests"
	@echo "  make clean              - Clean build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  make run-01             - Basic sprite rendering"
	@echo "  make run-02             - Animation system"
	@echo "  make run-03             - Sprite atlas loading"
	@echo "  make run-04             - Camera pan and zoom"
	@echo "  make run-05             - ECS render systems"
	@echo "  make run-06             - Visual effects"
	@echo "  make run-07             - TexturePacker fixtures demo"
	@echo "  make run-08             - Nested animation paths"
	@echo ""
	@echo "  make run-all            - Run all examples sequentially"
