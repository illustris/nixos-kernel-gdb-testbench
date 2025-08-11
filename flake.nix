{
	description = "Minimal kernel debugging testbench";

	inputs = {
		nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
	};

	outputs = { self, nixpkgs }: let
		system = "x86_64-linux";
		pkgs = import nixpkgs { inherit system; };
		lib = nixpkgs.lib // {
			indent = with lib; txt: let
				lines = splitString "\n" txt;
				# if the last line has n tabs, n+1 tabs need to be dropped from previous lines
				pivot = 1 + (pipe lines [
					last
					stringLength
				]);
			in concatStringsSep "\n" (
				map (
					line: let
						rightStr = substring pivot (stringLength line) line;
						leftStr = substring 0 pivot line;
						# Check for non-tab characters in the truncated section
						# If you hit the following assert, check your indentation
					in assert (replaceStrings ["\t"] [""] leftStr == ""); rightStr
				) lines
			);
		};
	in {
		# Development shell with useful tools
		devShells.${system}.default = pkgs.mkShell {
			buildInputs = with pkgs; [
				gdb
				qemu
				tmux
				socat
			];
			shellHook = lib.indent ''
				echo "Kernel debugging testbench environment"
				echo "Available commands:"
				echo "  nix run .#vm     - Start the test VM with GDB server"
				echo "  nix run .#gdb    - Connect GDB to the running VM"
				echo ""
			'';
		};

		# Test VM configuration with kernel debugging enabled
		nixosConfigurations.debugvm = lib.nixosSystem {
			inherit system;
			modules = [
				({ config, pkgs, lib, modulesPath, ... }: {
					imports = [
						"${modulesPath}/virtualisation/qemu-vm.nix"
					];

					# Auto-login as root for convenience
					services.getty.autologinUser = lib.mkForce "root";

					# Enable kernel debugging features
					boot.kernelParams = [
						"console=ttyS0,115200"
						"nokaslr"             # Disable KASLR for predictable addresses
						"kgdboc=ttyS0,115200" # KGDB over serial console
						# "kgdbwait"          # Wait for GDB connection on boot (commented out for now)
					];

					# Kernel patches for debugging support
					boot.kernelPatches = lib.singleton {
						name = "enable-kgdb";
						patch = null;
						extraStructuredConfig = with lib.kernel; {
							# Core debugging options
							DEBUG_KERNEL = yes;
							DEBUG_INFO = yes;
							DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT = yes;

							# KGDB configuration
							KGDB = yes;
							KGDB_SERIAL_CONSOLE = yes;
							KGDB_KDB = yes;
							KGDB_LOW_LEVEL_TRAP = yes;

							# Additional debugging features
							MAGIC_SYSRQ = yes;
							CONSOLE_POLL = yes;

							# Frame pointers for better stack traces
							FRAME_POINTER = yes;

							# Disable optimizations that interfere with debugging
							GDB_SCRIPTS = yes;
						};
					};

					# Minimal system configuration
					fileSystems."/" = {
						device = "/dev/disk/by-label/nixos";
						fsType = "ext4";
						autoResize = true;
					};

					# Disable unnecessary services for faster boot
					services.udisks2.enable = false;
					documentation.enable = false;

					# Basic networking
					networking.hostName = "debugvm";
					networking.useDHCP = lib.mkDefault true;

					# VM specific settings
					virtualisation = {
						diskSize = 4096;
						memorySize = 2048;
						cores = 2;
						graphics = false;

						qemu.options = [
							"-nographic"
							"-serial mon:stdio"
							"-s" # Enable GDB server on port 1234
						];
					};

					system.stateVersion = "24.05";
				})
			];
		};

		# Convenient apps for running VM and GDB
		apps.${system} = {
			# Start the VM with GDB server
			vm = {
				type = "app";
				program = toString (pkgs.writeScript "run-debug-vm" (lib.indent ''
					#!${pkgs.bash}/bin/bash
					echo "Starting debug VM with GDB server on port 1234..."
					echo "The VM will pause early in boot if kgdbwait is enabled."
					echo "Connect with: nix run .#gdb"
					echo ""
					${self.nixosConfigurations.debugvm.config.system.build.vm}/bin/run-debugvm-vm
				''));
			};

			# Connect GDB to the VM
			gdb = let
				kernel = self.nixosConfigurations.debugvm.config.boot.kernelPackages.kernel;
				kernelDev = kernel.dev;
				vmlinux = "${kernelDev}/vmlinux";

				# Extract kernel source for proper source directory access
				kernelSrc = pkgs.runCommand "kernel-src-extracted" {} (lib.indent ''
					mkdir -p $out
					tar -xf ${kernel.src} -C $out --strip-components=1
				'');

				# Generate the GDB scripts with constants.py
				gdbScripts = pkgs.runCommand "kernel-gdb-scripts" {
					nativeBuildInputs = [ pkgs.python3 ];
				} (lib.indent ''
					# Create the expected directory structure that vmlinux-gdb.py expects
					mkdir -p $out/scripts/gdb

					# Copy the GDB scripts if they exist, maintaining the structure
					if [ -d "${kernelDev}/lib/modules/${kernel.version}/source/scripts/gdb" ]; then
						cp -r ${kernelDev}/lib/modules/${kernel.version}/source/scripts/gdb/* $out/scripts/gdb/
						chmod -R u+w $out
					fi

					# Also create a top-level copy for direct access
					if [ -d "$out/scripts/gdb/linux" ]; then
						cp -r $out/scripts/gdb/* $out/ 2>/dev/null || true
					fi

					# Generate a basic constants.py if it doesn't exist
					if [ -f "$out/scripts/gdb/linux/constants.py.in" ] && [ ! -f "$out/scripts/gdb/linux/constants.py" ]; then
						echo "Generating constants.py from template..."

						# Create a basic constants.py with common values
						# This is a workaround since we don't have the full kernel build environment
						cat > $out/scripts/gdb/linux/constants.py << 'CONSTANTS_EOF'
					# Generated constants for GDB scripts
					# This is a simplified version for basic functionality

					import gdb

					# Basic constants that are commonly used
					LX_CONFIG_KALLSYMS = True
					LX_CONFIG_DEBUG_INFO = True
					LX_CONFIG_MODULES = True
					LX_CONFIG_MMU = True
					LX_CONFIG_64BIT = True
					LX_CONFIG_STACKTRACE = True
					LX_CONFIG_FRAME_POINTER = True
					LX_CONFIG_KGDB = True
					LX_CONFIG_GDB_SCRIPTS = True

					# Architecture
					LX_CONFIG_X86_64 = True

					# Memory constants
					LX_PAGE_SHIFT = 12
					LX_PAGE_SIZE = 1 << LX_PAGE_SHIFT
					LX_PAGE_MASK = ~(LX_PAGE_SIZE - 1)
					LX_THREAD_SIZE = 16384

					# Task struct constants
					LX_TASK_COMM_LEN = 16

					# Module constants
					LX_MODULE_NAME_LEN = 56

					# Kernel version (simplified)
					LX_KERNEL_VERSION = "${kernel.version}"

					# CPU constants
					LX_NR_CPUS = 512
					LX_HZ = 1000

					# GDB helper version info
					LX_GDBPARSED = True

					# Debug info settings - critical for script functionality
					LX_CONFIG_DEBUG_INFO_REDUCED = False
					LX_CONFIG_DEBUG_INFO_SPLIT = False
					LX_CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT = True

					# Module related
					LX_CONFIG_MODULES_TREE_LOOKUP = True

					# Additional configs to prevent errors
					LX_CONFIG_STACKDEPOT = True
					LX_CONFIG_PAGE_OWNER = True
					LX_CONFIG_SLUB_DEBUG = False
					LX_CONFIG_SLAB_FREELIST_HARDENED = False

					# Log levels
					LX_CONFIG_DEFAULT_MESSAGE_LOGLEVEL = 4
					LX_CONFIG_CONSOLE_LOGLEVEL_DEFAULT = 7

					# Filesystem constants (superblock flags)
					LX_SB_RDONLY = 1
					LX_SB_NOSUID = 2
					LX_SB_NODEV = 4
					LX_SB_NOEXEC = 8
					LX_SB_SYNCHRONOUS = 16
					LX_SB_MANDLOCK = 64
					LX_SB_DIRSYNC = 128  # Directory sync updates
					LX_SB_NOATIME = 1024
					LX_SB_NODIRATIME = 2048

					# VFS mount flags
					LX_MS_RDONLY = 1
					LX_MS_NOSUID = 2
					LX_MS_NODEV = 4
					LX_MS_NOEXEC = 8
					LX_MS_SYNCHRONOUS = 16
					LX_MS_REMOUNT = 32
					LX_MS_MANDLOCK = 64
					LX_MS_DIRSYNC = 128
					LX_MS_NOATIME = 1024
					LX_MS_NODIRATIME = 2048

					# Task state constants
					LX_TASK_RUNNING = 0
					LX_TASK_INTERRUPTIBLE = 1
					LX_TASK_UNINTERRUPTIBLE = 2
					LX_TASK_STOPPED = 4
					LX_TASK_TRACED = 8

					# Signal constants
					LX_SIGKILL = 9
					LX_SIGSTOP = 19

					# Module state constants
					LX_MODULE_STATE_LIVE = 0
					LX_MODULE_STATE_COMING = 1
					LX_MODULE_STATE_GOING = 2
					LX_MODULE_STATE_UNFORMED = 3
					CONSTANTS_EOF

						# Copy to top-level linux dir as well
						if [ -d "$out/linux" ]; then
							cp $out/scripts/gdb/linux/constants.py $out/linux/constants.py
						fi

						echo "Created constants.py successfully"
					elif [ ! -d "$out/scripts/gdb/linux" ]; then
						# No scripts found, create minimal structure
						mkdir -p $out/scripts/gdb/linux
						mkdir -p $out/linux
						cat > $out/scripts/gdb/linux/constants.py << 'CONSTANTS_EOF'
					# Minimal constants for GDB scripts
					import gdb

					LX_CONFIG_64BIT = True
					LX_CONFIG_X86_64 = True
					LX_CONFIG_KALLSYMS = True
					LX_CONFIG_DEBUG_INFO = True
					LX_CONFIG_DEBUG_INFO_REDUCED = False
					LX_CONFIG_GDB_SCRIPTS = True
					LX_PAGE_SHIFT = 12
					LX_GDBPARSED = True
					CONSTANTS_EOF

						cp $out/scripts/gdb/linux/constants.py $out/linux/constants.py

						# Create empty __init__.py
						touch $out/scripts/gdb/linux/__init__.py
						touch $out/linux/__init__.py
						echo "Created minimal GDB script structure"
					fi

					# List what we created
					echo "Contents of $out:"
					ls -la $out/
					if [ -d "$out/scripts/gdb" ]; then
						echo "Contents of $out/scripts/gdb:"
						ls -la $out/scripts/gdb/
					fi
				'');

				gdbInit = pkgs.writeText "gdbinit" (lib.indent ''
					# Load kernel symbols
					file ${vmlinux}

					# Set up source directories from extracted source
					dir ${kernelSrc}
					dir ${kernelSrc}/init
					dir ${kernelSrc}/kernel
					dir ${kernelSrc}/mm
					dir ${kernelSrc}/fs
					dir ${kernelSrc}/drivers
					dir ${kernelSrc}/arch/x86

					# Connect to QEMU GDB server
					target remote localhost:1234

					# Load kernel GDB scripts if available
					add-auto-load-safe-path ${kernelDev}/lib/modules/${kernel.version}/source/scripts/gdb
					add-auto-load-safe-path ${gdbScripts}

					# Try to load kernel python scripts with our generated constants
					python
					import sys
					import os

					# Add both the original and our generated scripts to path
					gdb_scripts_dir = "${kernelDev}/lib/modules/${kernel.version}/source/scripts/gdb"
					generated_scripts_dir = "${gdbScripts}"

					# First add our generated scripts (with constants.py)
					if os.path.exists(generated_scripts_dir):
						sys.path.insert(0, generated_scripts_dir)
						print(f"Added generated scripts from {generated_scripts_dir}")

					# Then add the original scripts
					if os.path.exists(gdb_scripts_dir):
						sys.path.insert(0, gdb_scripts_dir)
						print(f"Added original scripts from {gdb_scripts_dir}")

					# Try to import and load the scripts
					try:
						# Check if we can directly source the vmlinux-gdb.py which should handle imports
						vmlinux_gdb_path = None
						if os.path.exists(generated_scripts_dir + "/vmlinux-gdb.py"):
							vmlinux_gdb_path = generated_scripts_dir + "/vmlinux-gdb.py"
						elif os.path.exists(gdb_scripts_dir + "/vmlinux-gdb.py"):
							vmlinux_gdb_path = gdb_scripts_dir + "/vmlinux-gdb.py"

						if vmlinux_gdb_path:
							# The vmlinux-gdb.py script handles its own path setup
							gdb.execute("source " + vmlinux_gdb_path)
							print("Kernel GDB helper scripts loaded successfully")
							print("Available lx commands: lx-dmesg, lx-ps, lx-symbols, etc.")

							# Try to verify it worked
							try:
								import linux
								print("✓ linux module is now available")
							except:
								pass
						else:
							print("Warning: vmlinux-gdb.py not found")
					except ImportError as e:
						print(f"Could not load kernel GDB helper scripts: {e}")
						print("Basic debugging is still available")
					except Exception as e:
						print(f"Error loading GDB scripts: {e}")
					end

					# Set some useful breakpoints (examples with modern kernel functions)
					# Uncomment as needed:
					# break start_kernel
					# break kernel_clone      # Modern replacement for do_fork
					# break do_syscall_64     # x86_64 syscall entry
					# break __x64_sys_openat  # Modern open syscall
					# break schedule          # Process scheduler

					# Display useful info
					echo \nConnected to kernel debugger\n
					echo Kernel version: ${kernel.version}\n
					echo \nUseful commands:\n
					echo   c - continue execution\n
					echo   bt - show backtrace\n
					echo   info threads - list all threads\n
					echo   info functions <pattern> - search for functions\n
					echo   lx-symbols - load module symbols (kernel helper)\n
					echo   lx-dmesg - print kernel log buffer (kernel helper)\n
					echo   lx-ps - list processes (kernel helper)\n
					echo \nModern kernel function names:\n
					echo   kernel_clone - process creation (replaces do_fork)\n
					echo   do_syscall_64 - x86_64 syscall entry point\n
					echo   __x64_sys_* - system call implementations\n
					echo \nExample: break kernel_clone\n
					echo \n
				'');
			in {
				type = "app";
				program = toString (pkgs.writeScript "run-gdb" (lib.indent ''
					#!${pkgs.bash}/bin/bash
					echo "Connecting GDB to kernel at localhost:1234..."

					# Set up Python path for GDB scripts
					export PYTHONPATH="${gdbScripts}:${kernelDev}/lib/modules/${kernel.version}/source/scripts/gdb:$PYTHONPATH"

					# Check what's available
					if [ -d "${kernelDev}/lib/modules/${kernel.version}/source/scripts/gdb" ]; then
						echo "Kernel GDB scripts found"
					fi

					if [ -f "${gdbScripts}/linux/constants.py" ]; then
						echo "Generated constants.py available"
					fi

					${pkgs.gdb}/bin/gdb -x ${gdbInit}
				''));
			};
		};

		# Export kernel packages for inspection
		packages.${system} = rec {
			inherit (self.nixosConfigurations.debugvm.config.boot.kernelPackages) kernel;

			# Kernel source for reference
			kernelSource = pkgs.stdenv.mkDerivation {
				name = "kernel-source-${kernel.version}";
				src = kernel.src;
				dontBuild = true;
				dontFixup = true;
				installPhase = (lib.indent ''
					mkdir -p $out
					cp -r . $out/
				'');
			};

			# Kernel development files with debug symbols
			kernelDev = kernel.dev;

			# VM runner script
			vm-runner = pkgs.writeScriptBin "run-vm" (lib.indent ''
				#!${pkgs.bash}/bin/bash
				${self.nixosConfigurations.debugvm.config.system.build.vm}/bin/run-debugvm-vm
			'');
		};
	};
}
