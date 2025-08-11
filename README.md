# Minimal Kernel Debugging Testbench

A Nix flake providing a minimal environment for Linux kernel debugging using QEMU and GDB.

## Features

- **Pre-configured NixOS VM** with kernel debugging symbols and KGDB support
- **GDB integration** with automatic symbol loading and source mapping
- **Minimal boot time** with unnecessary services disabled
- **QEMU GDB server** listening on port 1234
- **Kernel configuration** optimized for debugging (KGDB, no KASLR, debug info)

## Prerequisites

- Nix with flakes enabled
- x86_64-linux system

## Quick Start

1. **Build the VM** (this will compile a debug kernel, may take some time):
   ```bash
   nix build .#nixosConfigurations.debugvm.config.system.build.vm
   ```

2. **Start the VM** with GDB server:
   ```bash
   nix run .#vm
   ```
   The VM will start with a GDB server listening on port 1234. If `kgdbwait` is enabled in kernel parameters, the kernel will pause early in boot waiting for GDB connection.

3. **In another terminal, connect GDB**:
   ```bash
   nix run .#gdb
   ```
   This will automatically:
   - Load kernel symbols
   - Set up source directories
   - Connect to the VM's GDB server
   - Load kernel GDB helper scripts (if available)

## Development Shell

Enter a development shell with debugging tools:
```bash
nix develop
```

This provides:
- `gdb` - The GNU debugger
- `qemu` - For running VMs
- `tmux` - Terminal multiplexer for managing sessions
- `socat` - For serial console connections

## Kernel Configuration

The kernel is built with the following debugging features enabled:

### Core Debugging
- `DEBUG_KERNEL` - Enable kernel debugging
- `DEBUG_INFO` - Include debug symbols
- `FRAME_POINTER` - Better stack traces

### KGDB Support
- `KGDB` - Kernel debugger
- `KGDB_SERIAL_CONSOLE` - Debug over serial
- `KGDB_KDB` - Kernel debugger shell
- `MAGIC_SYSRQ` - SysRq key support

### Boot Parameters
- `nokaslr` - Disable address space randomization
- `kgdboc=ttyS0,115200` - KGDB over serial console
- `kgdbwait` - Wait for debugger on boot (optional)

## Customization

### Modifying Kernel Configuration

Edit the `boot.kernelPatches` section in `flake.nix` to add more kernel debugging options:

```nix
boot.kernelPatches = lib.singleton {
  name = "enable-kgdb";
  patch = null;
  extraStructuredConfig = with lib.kernel; {
    # Add your options here
    DEBUG_SPINLOCK = yes;
    DEBUG_MUTEXES = yes;
    # etc...
  };
};
```

### Setting Breakpoints

Modify the GDB initialization in the `gdb` app to add default breakpoints:

```nix
# In the gdbInit text:
break start_kernel
break do_fork
break sys_open
```

### VM Resources

Adjust VM resources in the `virtualisation.vmVariant` section:

```nix
virtualisation = {
  memorySize = 4096;  # MB
  cores = 4;
  # ...
};
```

## Advanced Usage

### Manual GDB Connection

If you prefer to run GDB manually:

```bash
gdb /nix/store/.../vmlinux
(gdb) target remote localhost:1234
(gdb) continue
```

### Kernel Source Access

Build and access kernel source:
```bash
nix build .#kernelSource
ls result/
```

### Serial Console

The VM uses serial console on stdio. You can interact with it directly in the terminal where you started the VM.

## Troubleshooting

1. **VM doesn't start**: Ensure you have KVM support or add `virtualisation.qemu.package = pkgs.qemu_full;` for software emulation.

2. **GDB can't connect**: Make sure the VM is running and no firewall is blocking port 1234.

3. **Missing debug symbols**: The kernel build might take time. Ensure it completed successfully.

4. **Kernel panics immediately**: Try removing `kgdbwait` from kernel parameters if the kernel hangs waiting for debugger.

## Example Debugging Session

1. Start VM: `nix run .#vm`
2. Connect GDB: `nix run .#gdb`
3. Set a breakpoint: `(gdb) break kernel_clone` (or `break __x64_sys_openat` for file operations)
4. Continue execution: `(gdb) continue`
5. Trigger breakpoint (e.g., any process creation for kernel_clone, or file open for openat)
6. Examine state: `(gdb) bt` for backtrace, `(gdb) info registers`, etc.

**Note**: Function names have changed in modern kernels:
- `do_fork` → `kernel_clone` (process creation)
- `sys_open` → `__x64_sys_openat` (file operations)
- Use `info functions <pattern>` to find current function names

## References

- [KGDB Documentation](https://www.kernel.org/doc/html/latest/dev-tools/kgdb.html)
- [GDB Documentation](https://www.gnu.org/software/gdb/documentation/)
- [Linux Kernel Debugging](https://www.kernel.org/doc/html/latest/dev-tools/index.html)
