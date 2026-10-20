import Metal

/// Cached resource requirements used to preserve custom shadow inputs. No packet pruning or
/// command compaction: geometry and explicit context bindings are recorded as supplied.
struct PipelineResourceUsage {
    struct Slots {
        private var bits: UInt64 = 0

        mutating func insert(_ index: Int, count: Int = 1) {
            guard index >= 0, index < 64 else { return }
            for slot in index ..< min(index + max(count, 1), 64) { bits |= UInt64(1) << slot }
        }

        var isEmpty: Bool { bits == 0 }

        func contains(_ index: Int) -> Bool {
            // Future/custom slots outside the compact mask stay conservative, never disappear.
            index < 0 || index >= 64 || bits & (UInt64(1) << index) != 0
        }
    }

    struct Stage {
        var buffers = Slots()
        var textures = Slots()
        init(_ bindings: [MTLBinding]) {
            for binding in bindings where binding.isUsed {
                switch binding.type {
                case .buffer: buffers.insert(binding.index)
                case .texture:
                    textures.insert(binding.index, count: (binding as? MTLTextureBinding)?.arrayLength ?? 1)
                default: break
                }
            }
        }
    }

    let vertex: Stage
    let fragment: Stage

    init(reflection: MTLRenderPipelineReflection) {
        vertex = Stage(reflection.vertexBindings)
        fragment = Stage(reflection.fragmentBindings)
    }

}
