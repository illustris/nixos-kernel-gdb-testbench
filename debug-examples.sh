#!/usr/bin/env bash
# Example script for debugging specific kernel subsystems
# This example shows how to debug kernel operations with modern function names

cat << 'EOF'
# Example GDB Commands for Kernel Debugging (Linux 6.x)

# Once connected to GDB (nix run .#gdb), you can use these commands:

# 1. Set breakpoints for cgroup debugging (example from reference):
break ../kernel/cgroup/cgroup.c:2063   # Start of cgroup_setup_root
break ../kernel/cgroup/cgroup.c:1787   # Inside rebind_subsystem

# 2. Common kernel entry points (modern kernels):
break start_kernel                     # Kernel initialization
break kernel_init                      # First kernel thread
break kernel_clone                     # Process creation (replaces do_fork)
break do_syscall_64                    # x86_64 syscall entry point
break __x64_sys_openat                 # Modern open syscall (openat replaced open)
break __x64_sys_write                  # Write syscall
break __x64_sys_read                   # Read syscall

# 3. Memory management:
break __alloc_pages                   # Page allocation
break kfree                            # Memory deallocation  
break kmalloc                          # Kernel memory allocation
break __get_free_pages                # Get free pages

# 4. Process management:
break schedule                         # Process scheduler
break wake_up_process                  # Wake up a process
break copy_process                     # Core of fork/clone
break do_exit                          # Process exit

# 5. Useful GDB commands in kernel context:
info threads                           # List all kernel threads
thread <n>                             # Switch to thread n
bt                                     # Backtrace of current thread
frame <n>                              # Select stack frame
info registers                         # Show CPU registers
x/10i $pc                             # Display next 10 instructions
print <variable>                      # Print kernel variable value
p/x $lx_current()                     # Print current task struct (if lx scripts loaded)

# 6. Kernel-specific GDB scripts (if available):
lx-dmesg                              # Print kernel log buffer
lx-symbols                            # Load module symbols
lx-ps                                 # List processes
lx-lsmod                              # List loaded modules
lx-version                            # Show kernel version
lx-cmdline                            # Show kernel command line

# 7. Finding the right function names:
info functions sys_                   # List all syscall functions
info functions __x64_sys_             # List x86_64 syscalls
info functions *clone*                # Find clone-related functions
info functions *sched*                # Find scheduler functions

# 8. Watchpoints for data debugging:
watch <variable>                      # Break when variable changes
rwatch <variable>                     # Break on read access
awatch <variable>                     # Break on any access

# 9. Continue execution:
continue                              # Resume kernel execution
step                                  # Step one line
next                                  # Step over function calls
finish                                # Run until current function returns

# 10. Conditional breakpoints:
break kmalloc if size > 1024         # Break on large allocations
condition 1 current->pid == 1        # Make breakpoint 1 conditional

# 11. Examining kernel structures:
p init_task                           # Print init process task_struct
p jiffies                             # Print current jiffies
p nr_running                          # Number of running processes
x/s linux_banner                      # Print kernel version banner

EOF

echo ""
echo "To use these commands:"
echo "1. Start the VM: nix run .#vm"
echo "2. Connect GDB: nix run .#gdb"
echo "3. Copy and paste the commands you need"
echo ""
echo "Note: Function names change between kernel versions."
echo "Use 'info functions <pattern>' to find the right names."
echo ""
echo "For automated debugging, you can modify the gdbInit section in flake.nix"
