// Sampler — reads how busy the Mac is: CPU load from the kernel's per-core tick counters,
// memory pressure as macOS itself grades it, memory in use the way Activity Monitor counts
// it, and the processes using the most CPU. None of it needs any permission.

import Foundation
import Darwin

struct Load {
    enum Pressure: Int {
        case normal = 1, warning = 2, critical = 4
        var name: String {
            switch self {
            case .normal: "Normal"
            case .warning: "Warning"
            case .critical: "Critical"
            }
        }
    }

    /// Share of all cores busy since the last sample, 0 to 1, split by who was busy.
    var cpu = 0.0
    var user = 0.0
    var system = 0.0
    /// How much of memory the kernel counts as spoken for, 0 to 1, and its grade.
    var memoryPressure = 0.0
    var pressure = Pressure.normal
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
}

final class Sampler {
    private var lastTicks: [UInt32] = []

    func sample() -> Load {
        var load = Load()
        (load.cpu, load.user, load.system) = cpu()
        load.memoryPressure = 1 - Double(Self.sysctl("kern.memorystatus_level") ?? 100) / 100
        load.pressure = Load.Pressure(rawValue: Int(Self.sysctl("kern.memorystatus_vm_pressure_level") ?? 1)) ?? .normal
        load.memoryUsed = Self.memoryUsed()
        return load
    }

    /// Busy share of all cores since the last call, from the tick counters each core
    /// keeps for user, system, idle and nice time. The first call has nothing to compare
    /// with, so it reads 0.
    private func cpu() -> (Double, Double, Double) {
        var cores: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count) == KERN_SUCCESS,
              let info
        else { return (0, 0, 0) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        }
        let ticks = (0..<Int(count)).map { UInt32(bitPattern: info[$0]) }
        defer { lastTicks = ticks }
        guard lastTicks.count == ticks.count else { return (0, 0, 0) }

        var user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0
        for core in 0..<Int(cores) {
            let base = core * Int(CPU_STATE_MAX)
            // The counters wrap, so subtract with wrapping.
            func delta(_ state: Int32) -> UInt64 {
                UInt64(ticks[base + Int(state)] &- lastTicks[base + Int(state)])
            }
            user += delta(CPU_STATE_USER)
            system += delta(CPU_STATE_SYSTEM)
            idle += delta(CPU_STATE_IDLE)
            nice += delta(CPU_STATE_NICE)
        }
        let total = Double(user + system + idle + nice)
        guard total > 0 else { return (0, 0, 0) }
        return (Double(user + system + nice) / total, Double(user + nice) / total, Double(system) / total)
    }

    private static func sysctl(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    /// App memory, wired and compressed, as Activity Monitor's Memory Used adds them up.
    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pages = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
            + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(vm_kernel_page_size)
    }

    /// The processes using the most CPU, busiest first, as `ps` reports them: a share of
    /// one core, so a busy process can pass 100%. `ps` can see every user's processes,
    /// which this app couldn't read itself without being root.
    static func topProcesses(_ limit: Int) -> [(name: String, cpu: Double)] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-Aco", "pcpu=,comm="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()

        let rows = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> (String, Double)? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let cpu = Double(trimmed[..<space]) else { return nil }
            return (trimmed[space...].trimmingCharacters(in: .whitespaces), cpu)
        }
        return Array(rows.sorted { $0.1 > $1.1 }.prefix(limit))
    }
}
