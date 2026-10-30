# Related work and novelty analysis

This is a focused, source-checked comparison, not a systematic review. Links
below were checked against the paper abstract, publisher record, or project
documentation on 2026-10-29. Bibliographic metadata is included so that the
scope of each comparison can be audited rather than inferred from a keyword.

## Closest systems

### Triton-distributed

Size Zheng, Wenlei Bao, Qi Hou, Xuegui Zheng, Jin Fang, Chenhui Huang,
Tianqi Li, Haojie Duanmu, Renze Chen, et al., “Triton-distributed: Programming
Overlapping Kernels on Distributed AI Systems with the Triton Compiler,”
arXiv:2504.19442v3 (2025), submitted 28 April 2025 and revised 5 June 2025.
[arXiv record](https://arxiv.org/abs/2504.19442). The abstract describes
OpenSHMEM-compliant communication primitives, compiler-assisted joint
communication/computation optimization, and performance on up to 64 devices.
This project audits three source patterns from a pinned checkout and proves
properties only of a small Lean calculus. It does not verify the Triton
compiler, generated code, or the paper's performance claims.

### TileLink

Size Zheng, Jin Fang, Xuegui Zheng, Qi Hou, Wenlei Bao, Ningxin Zheng, Ziheng
Jiang, Dongyang Wang, Jianxi Ye, et al., “TileLink: Generating Efficient
Compute-Communication Overlapping Kernels using Tile-Centric Primitives,”
arXiv:2503.20313v3 (2025), submitted 26 March 2025 and revised 3 April 2025.
[arXiv record](https://arxiv.org/abs/2503.20313). TileLink separates
communication and computation through tile-centric primitives and lowers them
to overlapping low-level instructions. Its contribution is a compiler and
performance system; this artifact instead makes signal visibility and token
ordering explicit in a proof-oriented core. No equivalence to TileLink's
primitives or backend is claimed.

## Separation logic and protocol reasoning

* Ralf Jung, Robbert Krebbers, Jacques-Henri Jourdan, Bart Jacobs, Jacques
	Pichon-Pharabod, and Derek Dreyer, “Iris from the Ground Up: A Modular
	Foundation for Higher-Order Concurrent Separation Logic,” *Journal of
	Functional Programming* 28 (2018), e20. [Cambridge record](https://doi.org/10.1017/S0956796818000151)
	and [Iris project](https://iris-project.org/). Iris supplies a general
	higher-order concurrent separation-logic framework with mechanized proofs.
	The present model is a small transition system with explicit traces and
	witnesses, not an Iris development; it currently lacks Iris-style ownership,
	invariants, and a general concurrent separation-logic metatheory.
* Amin Timany, Robbert Krebbers, Derek Dreyer, and Lars Birkedal, “A Logical
	Approach to Type Soundness,” *Journal of the ACM* 71(6), Article 40 (2024).
	[Iris publication record](https://iris-project.org/pdfs/2024-jacm-logical-type-soundness-final.pdf)
	and [JACM record](https://doi.org/10.1145/3676954). This work demonstrates
	Iris-based logical type-soundness proofs. The Lean artifact's preservation
	lemmas are for its small encoded calculus only and are not a type-soundness
	proof for Triton Python, Triton IR, or generated code.
* Morten Krogh-Jespersen, Amin Timany, Marit Edna Ohlenbusch, Simon
	Oddershede Gregersen, and Lars Birkedal, “Aneris: A Mechanised Logic for
	Modular Reasoning about Distributed Systems,” *ESOP 2020* (2020).
	[Iris publication record](https://iris-project.org/pdfs/2020-esop-aneris-final.pdf)
	and [Rocq artifact](https://iris-project.org/artifacts/2020-esop-aneris.tar.gz).
	Aneris addresses distributed programs and modular reasoning about them. That
	is closer in distribution scope than ordinary sequential compiler proofs, but
	it does not make the current signal/token calculus an Aneris model; network
	semantics, crash behavior, and its proof methodology are not represented here.
* Jonas Kastberg Hinrichsen, Jesper Bengtson, and Robbert Krebbers, “Actris:
	Session-Type Based Reasoning in Separation Logic,” *POPL 2020* (2020).
	[Iris publication record](https://iris-project.org/pdfs/2020-popl-actris-final.pdf)
	and [project page](https://iris-project.org/actris). Actris gives
	session-typed protocols integrated with separation logic. It is relevant to
	collective participation and protocol reuse, but the current artifact has no
	session types, channel endpoints, or protocol duality. `wait`, `notify`, and
	`consume_token` are concrete constructors and not a session-typed API.
* Amin Timany, Simon Oddershede Gregersen, Léo Stefanesco, Jonas Kastberg
	Hinrichsen, Léon Gondelman, Abel Nieto, and Lars Birkedal, “Trillium:
	Higher-Order Concurrent and Distributed Separation Logic for Intensional
	Refinement,” *POPL 2024* (2024). [Iris publication record](https://iris-project.org/pdfs/2024-popl-trillium.pdf),
	[extended version](https://arxiv.org/pdf/2109.07863), and [Rocq development](https://github.com/logsem/trillium).
	Trillium is directly relevant to reasoning about distributed implementations
	through intensional refinement. The present artifact has no distributed
	refinement relation, network semantics, or logical relation connecting its
	Lean transitions to Triton-distributed executions.

## Weak memory and executable machine models

* Jan-Oliver Kaiser, Hoang-Hai Dang, Derek Dreyer, Ori Lahav, and Viktor
	Vafeiadis, “Strong Logic for Weak Memory: Reasoning About Release-Acquire
	Consistency in Iris,” *ECOOP 2017* (2017). [Paper and metadata](https://iris-project.org/pdfs/2017-ecoop-igps.pdf).
	This work gives a logic for release/acquire weak memory. It motivates treating
	notification visibility and ordering as target-specific assumptions, but it
	does not supply a GPU/NPU refinement for this artifact.
* Jade Alglave, Luc Maranget, Susmit Sarkar, and Peter Sewell, “Fences in Weak
	Memory Models,” *Computer-Aided Verification* (2010). [PDF and project
	resources](https://www.cl.cam.ac.uk/~pes20/weakmemory/). The herd-style
	executable model family makes allowed executions explicit. Our validator is
	much weaker: it parses source call shapes and does not enumerate executions,
	fences, scopes, or reorderings.
* Adam Chlipala, “Kami: A Platform for High-Level Parametric Hardware
	Specification and its Modular Verification,” *Proceedings of PLDI 2017*
	(2017). [ACM record](https://doi.org/10.1145/3062341.3062350) and
	[Kami repository](https://github.com/mit-plv/kami). Kami is an executable,
	parameterized hardware semantics with mechanized refinement proofs. It is a
	useful model for the missing backend layer, but this project has no hardware
	instruction semantics or refinement theorem.

## Compiler and GPU verification

* Xavier Rival and others, “GPUVerify: a Verification Framework for GPU
	Kernels,” *Proceedings of OOPSLA 2012* (2012). [ACM record](https://doi.org/10.1145/2384616.2384654)
	and [GPUVerify project](https://www.gpuverify.org/). GPUVerify targets
	data-race and barrier-divergence properties of GPU kernels through a
	translation and solver-backed analysis. The present artifact checks selected
	Python source patterns and proves conditional properties of a Lean core; it
	does not analyze divergent threads, pointer aliases, or generated GPU code.
* Xavier Leroy, “Formal Verification of a Realistic Compiler,” *Communications
	of the ACM* 52(7) (2009), 107–115. [DOI](https://doi.org/10.1145/1538788.1538814)
	and [CompCert documentation](https://compcert.org/). CompCert proves
	semantic preservation across a realistic compiler for a defined source and
	target language. That is the relevant standard for a future source-to-core
	or backend-refinement claim; this repository has neither a translation from
	Triton Python/MLIR nor a compiler simulation theorem.

## Comparison and limits

The nearest systems papers optimize or generate overlapping distributed kernels;
the formal-methods papers provide reusable logics, protocol abstractions,
weak-memory execution models, GPU analyses, or compiler refinement. The
current contribution, as supported by this repository, is narrower: a
source-audited prototype calculus with explicit notification transitions,
wait/token witnesses, conditional preservation/progress statements, and an
executable source-shape audit. That combination is not evidence of priority or
novelty. In particular, the source validator does not simulate the source,
prove API lowering, establish collective correctness, or justify the
`NotificationVisible` predicate on any CANN, CUDA, or OpenSHMEM implementation.

Before making a publication novelty claim, the project still needs a formal
source-to-core translation, backend/IR evidence, target memory-model tests, and
an independent review of the literature and theorem scopes.
