import Metal

/// Immutable direct argument usage of one compiled pipeline, never a union of other variants.
/// Nil usage means unreflected: keep its bindings. Reflection is consumed only at compilation.
struct PipelineResourceUsage {
    struct Slots {
        private var bits: UInt64 = 0

        mutating func insert(_ index: Int, count: Int = 1) {
            guard index >= 0, index < 64 else { return }
            for slot in index ..< min(index + max(count, 1), 64) { bits |= UInt64(1) << slot }
        }

        func contains(_ index: Int) -> Bool {
            // Future/custom slots outside the compact mask stay conservative, never disappear.
            index < 0 || index >= 64 || bits & (UInt64(1) << index) != 0
        }
    }

    struct Stage {
        var buffers = Slots()
        var textures = Slots()
        // Modern sampler reflection does not expose array length; preserve sampler arrays if
        // the stage uses a sampler. No samplers are needed when the stage uses none.
        var usesSamplers = false

        init(_ bindings: [MTLBinding]) {
            for binding in bindings where binding.isUsed {
                switch binding.type {
                case .buffer: buffers.insert(binding.index)
                case .texture:
                    textures.insert(binding.index, count: (binding as? MTLTextureBinding)?.arrayLength ?? 1)
                case .sampler: usesSamplers = true
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

    func uses(_ command: PacketCommand) -> Bool {
        switch command {
        case let .vertexBuffer(_,_,slot), let .perViewVertexBuffer(_,_,slot): return vertex.buffers.contains(slot.rawValue)
        case let .fragmentBuffer(_,_,slot), let .perViewFragmentBuffer(_,_,slot): return fragment.buffers.contains(slot.rawValue)
        case let .vertexTexture(_,slot): return vertex.textures.contains(slot.rawValue)
        case let .fragmentTexture(_,slot): return fragment.textures.contains(slot.rawValue)
        case let .fragmentPBRTexture(_,type): return fragment.textures.contains(type.index)
        case .fragmentSampler: return fragment.usesSamplers
        case .custom: return true
        }
    }
}
