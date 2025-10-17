# Alien Signals Reactive System Deep Dive

> This document uses Mermaid diagrams to deeply reveal the core principles and implementation mechanisms of the Alien Signals reactive system

## 📋 Table of Contents

- [1. System Architecture Overview](#1-system-architecture-overview)
- [2. Core Data Structures](#2-core-data-structures)
- [3. Dependency Tracking Mechanism](#3-dependency-tracking-mechanism)
- [4. Update Propagation Algorithm](#4-update-propagation-algorithm)
- [5. Batch Update Optimization](#5-batch-update-optimization)
- [6. Dirty Checking Strategy](#6-dirty-checking-strategy)
- [7. Memory Management](#7-memory-management)
- [8. Circular Dependency Detection](#8-circular-dependency-detection)
- [9. Complete Execution Flow](#9-complete-execution-flow)

---

## 1. System Architecture Overview

### 1.1 Three-Layer Architecture Design

Alien Signals adopts a three-layer architecture design, gradually abstracting from bottom to top:

```mermaid
graph TB
    subgraph Application Layer
        A1[User Code]
        A2[Business Logic]
    end
    
    subgraph High-Level API Layer
        B1[ref - Reference Wrapper]
        B2[reactive - Object Proxy]
        B3[watch - Watcher]
        B4[watchEffect - Auto Watch]
    end
    
    subgraph Core Reactive Layer
        C1[signal - Basic Signal]
        C2[computed - Computed Property]
        C3[effect - Side Effect]
        C4[effectScope - Scope]
    end
    
    subgraph Low-Level Infrastructure
        D1[Link System - Doubly Linked List]
        D2[Bitwise Flags - State Management]
        D3[Global State - Context Tracking]
        D4[Batch Queue - Performance Optimization]
    end
    
    A1 --> B1
    A2 --> B2
    A1 --> B3
    A2 --> B4
    
    B1 --> C1
    B2 --> C1
    B3 --> C3
    B4 --> C3
    
    C1 --> D1
    C2 --> D1
    C2 --> D2
    C3 --> D2
    C3 --> D3
    C4 --> D4
    
    style A1 fill:#e1f5e1
    style A2 fill:#e1f5e1
    style B1 fill:#fff4e6
    style B2 fill:#fff4e6
    style B3 fill:#fff4e6
    style B4 fill:#fff4e6
    style C1 fill:#e3f2fd
    style C2 fill:#e3f2fd
    style C3 fill:#e3f2fd
    style C4 fill:#e3f2fd
    style D1 fill:#fce4ec
    style D2 fill:#fce4ec
    style D3 fill:#fce4ec
    style D4 fill:#fce4ec
```

### 1.2 Core Component Relationships

```mermaid
classDiagram
    class Signal {
        +value: any
        +subs: Link
        +subsTail: Link
        +flags: number
        +get() any
        +set(value) void
    }
    
    class Computed {
        +getter: function
        +cachedValue: any
        +deps: Link
        +depsTail: Link
        +subs: Link
        +subsTail: Link
        +flags: number
        +get() any
        +update() void
    }
    
    class Effect {
        +fn: function
        +deps: Link
        +depsTail: Link
        +flags: number
        +run() void
        +stop() void
    }
    
    class Link {
        +dep: Signal|Computed
        +sub: Effect|Computed
        +prevSub: Link
        +nextSub: Link
        +prevDep: Link
        +nextDep: Link
    }
    
    class EffectScope {
        +effects: Effect[]
        +run(fn) any
        +stop() void
    }
    
    Signal "1" --> "*" Link: subscribers
    Computed "1" --> "*" Link: subscribers
    Computed "1" --> "*" Link: dependencies
    Effect "1" --> "*" Link: dependencies
    EffectScope "1" o-- "*" Effect: manages
    
    Link --> Signal: points to dep
    Link --> Computed: points to dep
    Link --> Effect: points to sub
    Link --> Computed: points to sub
```

---

## 2. Core Data Structures

### 2.1 Signal Structure

Signal is the most basic reactive unit that stores mutable values:

```mermaid
graph LR
    subgraph Signal Object
        A[value: Current Value]
        B[subs: Subscribers Head]
        C[subsTail: Subscribers Tail]
        D[flags: State Flags]
        E[marker: Type Marker]
    end
    
    B --> F[Link 1]
    F --> G[Link 2]
    G --> H[Link 3]
    C --> H
    
    style A fill:#4CAF50
    style B fill:#2196F3
    style C fill:#2196F3
```

**Bitwise Flag System**:

```mermaid
graph TD
    A[ReactiveFlags Bitwise Operations] --> B[None = 0]
    A --> C[Mutable = 1]
    A --> D[Watching = 2]
    A --> E[RecursedCheck = 4]
    A --> F[Recursed = 8]
    A --> G[Dirty = 16]
    A --> H[Pending = 32]
    
    I[EffectFlags Additional] --> J[Queued = 64]
    
    K[Flag Combination Examples]
    K --> L[Dirty | Pending = 48]
    K --> M[Watching | Queued = 66]
    
    style A fill:#FF9800
    style I fill:#FF9800
    style K fill:#9C27B0
```

### 2.2 Link Doubly Linked List Node

Link is the core structure connecting dependencies and subscribers:

```mermaid
graph TB
    subgraph "Link Node Complete Structure"
        L[Link Object]
        L --> D[dep: Dependency Object]
        L --> S[sub: Subscriber Object]
        L --> PS[prevSub: Previous Subscriber]
        L --> NS[nextSub: Next Subscriber]
        L --> PD[prevDep: Previous Dependency]
        L --> ND[nextDep: Next Dependency]
    end
    
    subgraph "Vertical List - Signal's Subscribers"
        Signal --> L1[Link1]
        L1 -.prevSub.-> L2[Link2]
        L2 -.nextSub.-> L1
        L2 -.prevSub.-> L3[Link3]
        L3 -.nextSub.-> L2
    end
    
    subgraph "Horizontal List - Effect's Dependencies"
        Effect --> L1
        L1 -.prevDep.-> L4[Link4]
        L4 -.nextDep.-> L1
        L4 -.prevDep.-> L5[Link5]
        L5 -.nextDep.-> L4
    end
    
    style L fill:#FF6B6B
    style Signal fill:#4CAF50
    style Effect fill:#FF9800
```

### 2.3 Global State Management

```mermaid
stateDiagram-v2
    [*] --> Idle: System Initialization
    
    Idle --> Tracking: Start Executing Effect/Computed
    
    state Tracking {
        [*] --> SetActiveSub
        SetActiveSub --> ExecuteFunction
        ExecuteFunction --> AccessSignal
        AccessSignal --> AutoLink
        AutoLink --> ExecuteFunction: Continue Execution
        ExecuteFunction --> [*]: Execution Complete
    }
    
    Tracking --> Idle: Clear activeSub
    
    Idle --> Batching: startBatch()
    
    state Batching {
        [*] --> IncrementDepth
        IncrementDepth --> ModifySignals
        ModifySignals --> QueueEffects
        QueueEffects --> ModifySignals: More Modifications
        QueueEffects --> [*]: endBatch()
    }
    
    Batching --> Flushing: batchDepth == 0
    
    state Flushing {
        [*] --> ProcessQueue
        ProcessQueue --> RunEffect
        RunEffect --> ProcessQueue: Next
        ProcessQueue --> [*]: Queue Empty
    }
    
    Flushing --> Idle
    
    note right of Tracking
        activeSub: Effect | Computed
        Automatic dependency collection
    end note
    
    note right of Batching
        batchDepth: number
        queuedEffects: Effect[]
    end note
```

---

## 3. Dependency Tracking Mechanism

### 3.1 Automatic Dependency Tracking Flow

```mermaid
sequenceDiagram
    participant User as User Code
    participant E as Effect
    participant G as Global State
    participant S1 as Signal A
    participant S2 as Signal B
    participant L as Link System
    
    User->>E: effect(fn)
    activate E
    Note over E: Create Effect Object
    
    E->>E: First Execution
    E->>G: setActiveSub(effect)
    Note over G: activeSub = effect
    
    E->>E: Execute Function Body
    E->>S1: Access signalA()
    activate S1
    S1->>G: Check activeSub
    G-->>S1: Return effect
    S1->>L: link(signalA, effect)
    
    Note over L: Create Link Node<br/>Connect signalA and effect
    L-->>S1: Dependency Established
    S1-->>E: Return Value
    deactivate S1
    
    E->>S2: Access signalB()
    activate S2
    S2->>G: Check activeSub
    G-->>S2: Return effect
    S2->>L: link(signalB, effect)
    
    Note over L: Create Second Link Node<br/>Connect signalB and effect
    L-->>S2: Dependency Established
    S2-->>E: Return Value
    deactivate S2
    
    E->>G: setActiveSub(nil)
    Note over G: activeSub = nil
    
    E->>User: Effect Creation Complete
    deactivate E
    
    Note over E,L: Now effect depends on<br/>signalA and signalB
```

### 3.2 Detailed Link Creation Process

```mermaid
flowchart TD
    Start([Call link Function]) --> Input[Input: dep, sub]
    
    Input --> CreateLink[Create Link Object]
    CreateLink --> SetDep[link.dep = dep]
    SetDep --> SetSub[link.sub = sub]
    
    SetSub --> CheckCircular{Check Circular Dependency}
    CheckCircular -->|Found| Error[Throw Error]
    CheckCircular -->|None| InsertSubs[Insert into dep.subs List]
    
    InsertSubs --> CheckSubsHead{subs Empty?}
    CheckSubsHead -->|Yes| SetSubsHead[dep.subs = link<br/>dep.subsTail = link]
    CheckSubsHead -->|No| AppendSubs[link.prevSub = dep.subsTail<br/>dep.subsTail.nextSub = link<br/>dep.subsTail = link]
    
    SetSubsHead --> InsertDeps[Insert into sub.deps List]
    AppendSubs --> InsertDeps
    
    InsertDeps --> CheckDepsHead{deps Empty?}
    CheckDepsHead -->|Yes| SetDepsHead[sub.deps = link<br/>sub.depsTail = link]
    CheckDepsHead -->|No| AppendDeps[link.prevDep = sub.depsTail<br/>sub.depsTail.nextDep = link<br/>sub.depsTail = link]
    
    SetDepsHead --> Success([Link Created Successfully])
    AppendDeps --> Success
    
    Error --> End([End])
    Success --> End
    
    style Start fill:#4CAF50
    style Success fill:#4CAF50
    style Error fill:#f44336
    style CheckCircular fill:#FF9800
```

### 3.3 Dependency Network Visualization

```mermaid
graph TB
    subgraph "Complete Dependency Network"
        S1[Signal: price]
        S2[Signal: quantity]
        S3[Signal: discount]
        
        C1[Computed: subtotal]
        C2[Computed: total]
        
        E1[Effect: updateUI]
        E2[Effect: logChange]
    end
    
    S1 -->|Link1| C1
    S2 -->|Link2| C1
    
    C1 -->|Link3| C2
    S3 -->|Link4| C2
    
    C2 -->|Link5| E1
    C2 -->|Link6| E2
    
    style S1 fill:#4CAF50
    style S2 fill:#4CAF50
    style S3 fill:#4CAF50
    style C1 fill:#2196F3
    style C2 fill:#2196F3
    style E1 fill:#FF9800
    style E2 fill:#FF9800
```

---

## 4. Update Propagation Algorithm

### 4.1 Signal Update Flow

```mermaid
flowchart TD
    Start([Signal Value Changed]) --> SetValue[signal.set newValue]
    
    SetValue --> CheckBatch{Check Batch Mode}
    CheckBatch -->|batchDepth > 0| Batching[Batch Mode]
    CheckBatch -->|batchDepth == 0| Immediate[Immediate Mode]
    
    Batching --> QueueOnly[Mark Only, Don't Execute]
    QueueOnly --> MarkDirty[Mark Subscribers as Dirty]
    
    Immediate --> DirectNotify[Notify Subscribers Immediately]
    DirectNotify --> MarkDirty
    
    MarkDirty --> IterSubs[Iterate subs List]
    IterSubs --> CurrentSub[Get Current Link]
    
    CurrentSub --> CheckSubType{Subscriber Type?}
    
    CheckSubType -->|Computed| NotifyComputed[Mark Computed Dirty]
    CheckSubType -->|Effect| NotifyEffect[Mark Effect Dirty]
    
    NotifyComputed --> PropagateSubs[Propagate to Subscribers]
    NotifyEffect --> AddToQueue[Add to Execution Queue]
    
    PropagateSubs --> MoreSubs{More Subscribers?}
    AddToQueue --> MoreSubs
    
    MoreSubs -->|Yes| IterSubs
    MoreSubs -->|No| CheckMode{Check Mode}
    
    CheckMode -->|Immediate| Flush[Execute Queue]
    CheckMode -->|Batch| WaitBatch[Wait for endBatch]
    
    Flush --> RunEffects[Run All Effects]
    WaitBatch --> End([Wait for Batch End])
    RunEffects --> End
    
    style Start fill:#4CAF50
    style Flush fill:#FF9800
    style RunEffects fill:#FF9800
```

### 4.2 Update Propagation Sequence

```mermaid
sequenceDiagram
    participant User as User Code
    participant S as Signal
    participant C as Computed
    participant E as Effect
    participant Q as Execution Queue
    
    Note over S,E: === Initial State: All Objects Clean ===
    
    User->>S: signal.set(newValue)
    activate S
    Note over S: value = newValue
    
    S->>S: Iterate subs List
    
    S->>C: Notify Computed
    activate C
    Note over C: flags |= Dirty (16)
    C->>C: Iterate Own subs
    C->>E: Notify Effect
    deactivate C
    
    activate E
    Note over E: flags |= Dirty (16)<br/>flags |= Queued (64)
    E->>Q: Add to Queue
    deactivate E
    
    S->>S: Check batchDepth
    
    alt batchDepth == 0 (Immediate Mode)
        S->>Q: flush()
        activate Q
        Q->>E: Run Effect
        activate E
        E->>C: Read Computed
        activate C
        Note over C: Detected Dirty<br/>Recompute
        C->>S: Read Signal
        S-->>C: Return New Value
        C->>C: Update Cache<br/>Clear Dirty
        C-->>E: Return Computed Result
        deactivate C
        E->>E: Execute Side Effect Function
        E->>E: Clear Dirty and Queued
        E-->>Q: Complete
        deactivate E
        Q-->>S: Flush Complete
        deactivate Q
    else batchDepth > 0 (Batch Mode)
        Note over Q: Wait for endBatch()
    end
    
    S-->>User: Set Complete
    deactivate S
```

### 4.3 Dirty Propagation Layers

```mermaid
graph TD
    A[Signal Changed<br/>Layer 0] -->|Immediate Mark| B1[Computed 1<br/>Dirty - Layer 1]
    A -->|Immediate Mark| B2[Computed 2<br/>Dirty - Layer 1]
    
    B1 -->|Propagate| C1[Computed 3<br/>Dirty - Layer 2]
    B2 -->|Propagate| C2[Effect 1<br/>Dirty + Queued - Layer 2]
    
    C1 -->|Propagate| D1[Effect 2<br/>Dirty + Queued - Layer 3]
    
    style A fill:#4CAF50,color:#fff
    style B1 fill:#FFA726
    style B2 fill:#FFA726
    style C1 fill:#FF7043
    style C2 fill:#FF7043
    style D1 fill:#F44336,color:#fff
```

---

## 5. Batch Update Optimization

### 5.1 Batch Update Mechanism

```mermaid
sequenceDiagram
    participant User as User Code
    participant Batch as Batch System
    participant S1 as Signal A
    participant S2 as Signal B
    participant E as Effect
    participant Q as Queue
    
    User->>Batch: startBatch()
    Note over Batch: batchDepth = 1
    
    User->>S1: signalA(1)
    S1->>E: Mark Dirty + Queued
    E->>Q: Add to Queue
    Note over Q: queuedEffects[0] = Effect
    
    User->>S2: signalB(2)
    S2->>E: Try to Mark
    Note over E: Already Queued, Skip
    
    User->>S1: signalA(10)
    S1->>E: Try to Mark
    Note over E: Already Queued, Skip
    
    User->>S2: signalB(20)
    S2->>E: Try to Mark
    Note over E: Already Queued, Skip
    
    User->>Batch: endBatch()
    Note over Batch: batchDepth = 0
    
    Batch->>Q: flush()
    Q->>E: Run Effect (Only Once)
    activate E
    E->>S1: Read Latest Value
    S1-->>E: 10
    E->>S2: Read Latest Value
    S2-->>E: 20
    E->>E: Execute Side Effect<br/>print("A=10, B=20")
    E->>E: Clear Dirty + Queued
    deactivate E
    
    Note over User,Q: 4 Modifications, 1 Effect Execution ✨
```

### 5.2 Nested Batch Updates

```mermaid
flowchart TD
    Start([User Code Starts]) --> Batch1[startBatch]
    Batch1 --> Depth1[batchDepth = 1]
    
    Depth1 --> Modify1[Modify Signal A]
    Modify1 --> Batch2[startBatch - Nested]
    Batch2 --> Depth2[batchDepth = 2]
    
    Depth2 --> Modify2[Modify Signal B]
    Modify2 --> Modify3[Modify Signal C]
    
    Modify3 --> End2[endBatch]
    End2 --> Depth3[batchDepth = 1]
    Depth3 --> CheckDepth1{batchDepth == 0?}
    CheckDepth1 -->|No| Continue[Continue Batch Mode]
    
    Continue --> Modify4[Modify Signal D]
    Modify4 --> End1[endBatch]
    End1 --> Depth4[batchDepth = 0]
    
    Depth4 --> CheckDepth2{batchDepth == 0?}
    CheckDepth2 -->|Yes| Flush[flush Execute Queue]
    
    Flush --> RunAll[Run All Effects<br/>Execute Once]
    RunAll --> Done([Complete])
    
    style Start fill:#4CAF50
    style Flush fill:#FF9800
    style RunAll fill:#FF9800
    style Done fill:#4CAF50
```

### 5.3 Performance Comparison

```mermaid
gantt
    title Batch Update Performance Comparison
    dateFormat X
    axisFormat %L ms
    
    section Without Batch
    signal(1)      :a1, 0, 10
    Effect Run 1   :a2, 10, 20
    signal(2)      :a3, 30, 10
    Effect Run 2   :a4, 40, 20
    signal(3)      :a5, 60, 10
    Effect Run 3   :a6, 70, 20
    
    section With Batch
    startBatch     :b1, 0, 5
    signal(1)      :b2, 5, 10
    signal(2)      :b3, 15, 10
    signal(3)      :b4, 25, 10
    endBatch       :b5, 35, 5
    Effect Run     :b6, 40, 20
```

---

## 6. Dirty Checking Strategy

### 6.1 Computed Lazy Evaluation

```mermaid
flowchart TD
    Start([Read Computed Value]) --> CheckDirty{Check Dirty Flag}
    
    CheckDirty -->|Clean 0| ReturnCache[Return Cached Value Directly]
    CheckDirty -->|Dirty 16| CheckDeps[Check if Dependencies Really Changed]
    
    CheckDeps --> IterDeps[Iterate deps List]
    IterDeps --> GetDep[Get Dependency Object]
    
    GetDep --> DepType{Dependency Type?}
    
    DepType -->|Signal| CheckSignalChange{Signal Value Changed?}
    DepType -->|Computed| RecursiveCheck[Recursively Check Computed]
    
    CheckSignalChange -->|Yes| NeedRecompute[Confirm Need to Recompute]
    CheckSignalChange -->|No| NextDep[Check Next Dependency]
    
    RecursiveCheck -->|Dirty| NeedRecompute
    RecursiveCheck -->|Clean| NextDep
    
    NextDep --> MoreDeps{More Dependencies?}
    MoreDeps -->|Yes| IterDeps
    MoreDeps -->|No| AllClean[All Dependencies Unchanged]
    
    AllClean --> ClearDirty1[Clear Dirty Flag]
    ClearDirty1 --> ReturnCache
    
    NeedRecompute --> PurgeDeps[Clear Old Dependency Links]
    PurgeDeps --> SetActive[Set activeSub]
    SetActive --> ExecGetter[Execute getter Function]
    ExecGetter --> AutoTrack[Auto Track New Dependencies]
    AutoTrack --> UpdateCache[Update Cached Value]
    UpdateCache --> ClearDirty2[Clear Dirty Flag]
    ClearDirty2 --> ReturnNew[Return New Value]
    
    ReturnCache --> End([End])
    ReturnNew --> End
    
    style Start fill:#2196F3
    style ExecGetter fill:#FF9800
    style AutoTrack fill:#4CAF50
    style ReturnCache fill:#9C27B0
    style ReturnNew fill:#9C27B0
```

### 6.2 Smart Dirty Check Flow

```mermaid
sequenceDiagram
    participant E as Effect
    participant C as Computed
    participant S1 as Signal A
    participant S2 as Signal B
    
    Note over E,S2: === Scenario: Computed Depends on Two Signals ===
    
    E->>C: Read computed()
    activate C
    Note over C: flags & Dirty == 16<br/>Need to Check Dependencies
    
    C->>C: Iterate deps List
    
    C->>S1: Check Signal A
    activate S1
    Note over S1: Value Unchanged
    S1-->>C: Return false (No Update Needed)
    deactivate S1
    
    C->>S2: Check Signal B
    activate S2
    Note over S2: Value Unchanged
    S2-->>C: Return false (No Update Needed)
    deactivate S2
    
    Note over C: All Dependencies Unchanged<br/>No Need to Recompute
    
    C->>C: Clear Dirty Flag<br/>flags &= ~Dirty
    C-->>E: Return Cached Value (Fast Path ✨)
    deactivate C
    
    Note over E,S2: === Contrast: If Signal B Changed ===
    
    E->>C: Read computed()
    activate C
    C->>S1: Check Signal A
    activate S1
    S1-->>C: false (No Change)
    deactivate S1
    
    C->>S2: Check Signal B
    activate S2
    Note over S2: Value Changed!
    S2-->>C: true (Update Needed)
    deactivate S2
    
    Note over C: Detected Dependency Change<br/>Need to Recompute
    
    C->>C: Execute getter Function
    C->>S1: Read New Value
    C->>S2: Read New Value
    C->>C: Calculate Result<br/>Update Cache<br/>Clear Dirty
    C-->>E: Return New Computed Value
    deactivate C
```

### 6.3 Bitwise Flag Operations

```mermaid
graph TD
    subgraph "Flag Setting Operations"
        A[Original flags = 0]
        A -->|flags OR Dirty| B[flags = 16]
        B -->|flags OR Queued| C[flags = 80]
        C -->|flags OR Watching| D[flags = 82]
    end
    
    subgraph "Flag Checking Operations"
        E[flags = 82]
        E -->|flags AND Dirty| F{Result != 0?}
        F -->|Yes| G[Is Dirty]
        F -->|No| H[Not Dirty]
        
        E -->|flags AND Queued| I{Result != 0?}
        I -->|Yes| J[Is Queued]
        I -->|No| K[Not Queued]
    end
    
    subgraph "Flag Clearing Operations"
        L[flags = 82]
        L -->|flags AND NOT Dirty| M[flags = 66]
        M -->|flags AND NOT Queued| N[flags = 2]
    end
    
    style A fill:#E8F5E9
    style G fill:#4CAF50
    style J fill:#4CAF50
    style N fill:#2196F3
```

---

## 7. Memory Management

### 7.1 Dependency Cleanup Mechanism

```mermaid
flowchart TD
    Start([Effect Stopped or Re-executed]) --> CheckDeps{Check deps List}
    
    CheckDeps -->|Empty| NoCleanup[No Cleanup Needed]
    CheckDeps -->|Not Empty| StartPurge[Start purgeDeps]
    
    StartPurge --> GetFirst[Get deps Head Node]
    GetFirst --> Loop[Iterate List]
    
    Loop --> CurrentLink[Current Link Node]
    
    CurrentLink --> Unlink1[Remove from dep.subs]
    Unlink1 --> UpdatePrev{prevSub Exists?}
    
    UpdatePrev -->|Yes| SetPrevNext[prevSub.nextSub = nextSub]
    UpdatePrev -->|No| UpdateHead[dep.subs = nextSub]
    
    SetPrevNext --> UpdateNext{nextSub Exists?}
    UpdateHead --> UpdateNext
    
    UpdateNext -->|Yes| SetNextPrev[nextSub.prevSub = prevSub]
    UpdateNext -->|No| UpdateTail[dep.subsTail = prevSub]
    
    SetNextPrev --> NextLink{More Links?}
    UpdateTail --> NextLink
    
    NextLink -->|Yes| Loop
    NextLink -->|No| ClearPointers[Clear deps and depsTail]
    
    ClearPointers --> GC[Link Nodes Await GC]
    GC --> Done([Cleanup Complete])
    
    NoCleanup --> Done
    
    style Start fill:#FF9800
    style GC fill:#9C27B0
    style Done fill:#4CAF50
```

### 7.2 Memory Cleanup Sequence

```mermaid
sequenceDiagram
    participant E as Effect
    participant L1 as Link 1
    participant L2 as Link 2
    participant S1 as Signal A
    participant S2 as Signal B
    
    Note over E,S2: === Clean Old Dependencies Before Effect Re-execution ===
    
    E->>E: Preparing to Re-execute
    E->>E: purgeDeps()
    
    E->>L1: Get deps Head Node
    activate L1
    
    L1->>S1: Remove from subs List
    activate S1
    Note over S1: Update List Pointers<br/>If head: subs = nextSub<br/>If tail: subsTail = prevSub<br/>Otherwise: Connect prev and next
    S1-->>L1: Removal Complete
    deactivate S1
    
    L1-->>E: Processing Complete
    deactivate L1
    
    E->>L2: Get Next Node
    activate L2
    
    L2->>S2: Remove from subs List
    activate S2
    Note over S2: Update List Pointers
    S2-->>L2: Removal Complete
    deactivate S2
    
    L2-->>E: Processing Complete
    deactivate L2
    
    E->>E: deps = nil<br/>depsTail = nil
    
    Note over L1,L2: Link Objects No References<br/>Await Garbage Collection 🗑️
    
    Note over E,S2: === Execute Function, Establish New Dependencies ===
    
    E->>E: Execute Function Body
    Note over E: Access Signal<br/>Auto Create New Links
```

### 7.3 EffectScope Batch Cleanup

```mermaid
graph TB
    subgraph "Effects Managed by EffectScope"
        ES[EffectScope]
        ES --> E1[Effect 1]
        ES --> E2[Effect 2]
        ES --> E3[Effect 3]
        ES --> E4[Effect 4]
    end
    
    E1 --> L1[Link 1-1]
    E1 --> L2[Link 1-2]
    E2 --> L3[Link 2-1]
    E3 --> L4[Link 3-1]
    E3 --> L5[Link 3-2]
    E3 --> L6[Link 3-3]
    E4 --> L7[Link 4-1]
    
    L1 --> S1[Signal A]
    L2 --> S2[Signal B]
    L3 --> S3[Signal C]
    L4 --> S1
    L5 --> S4[Signal D]
    L6 --> S2
    L7 --> S5[Signal E]
    
    ES -.Call scope.stop.-> Clear[Cleanup All Effects]
    Clear -.-> Cleanup[Batch Cleanup All Links]
    
    style ES fill:#9C27B0
    style Clear fill:#f44336
    style Cleanup fill:#f44336
```

---

## 8. Circular Dependency Detection

### 8.1 Circular Dependency Detection Algorithm

```mermaid
flowchart TD
    Start([link Call]) --> Input[Input: dep, sub]
    
    Input --> InitCheck[Initialize Detection]
    InitCheck --> SetFlag[dep.flags OR RecursedCheck]
    
    SetFlag --> CheckDeps{sub Has Dependencies?}
    CheckDeps -->|No| Safe1[Safe: First Dependency]
    CheckDeps -->|Yes| StartTraverse[Start Traversing sub.deps]
    
    StartTraverse --> GetLink[Get Link Node]
    GetLink --> CheckTarget{link.dep == dep?}
    
    CheckTarget -->|Yes| Circular1[❌ Direct Circular Found]
    CheckTarget -->|No| CheckType{link.dep is Computed?}
    
    CheckType -->|No| NextLink1[Next Link]
    CheckType -->|Yes| CheckFlag{dep.flags & RecursedCheck?}
    
    CheckFlag -->|Yes| Circular2[❌ Indirect Circular Found]
    CheckFlag -->|No| RecursiveCall[Recursively Check link.dep]
    
    RecursiveCall --> Found{Circular Found?}
    Found -->|Yes| Circular3[❌ Circular Dependency]
    Found -->|No| NextLink2[Next Link]
    
    NextLink1 --> MoreLinks1{More Links?}
    NextLink2 --> MoreLinks2{More Links?}
    
    MoreLinks1 -->|Yes| GetLink
    MoreLinks1 -->|No| Safe2[Safe: No Circular]
    MoreLinks2 -->|Yes| GetLink
    MoreLinks2 -->|No| Safe2
    
    Safe1 --> CreateLink[Create Link Node]
    Safe2 --> ClearFlag[Clear RecursedCheck Flag]
    ClearFlag --> CreateLink
    
    Circular1 --> Error[Throw Error]
    Circular2 --> Error
    Circular3 --> Error
    
    CreateLink --> Success([✅ Link Successful])
    Error --> End([❌ Failed])
    Success --> End
    
    style Start fill:#4CAF50
    style Success fill:#4CAF50
    style Error fill:#f44336
    style Circular1 fill:#f44336
    style Circular2 fill:#f44336
    style Circular3 fill:#f44336
```

### 8.2 Circular Dependency Examples

```mermaid
graph TB
    subgraph "Direct Circular - Immediate Detection"
        A1[Computed A]
        B1[Computed B]
        A1 -.Attempting to Depend.-> B1
        B1 -.Already Depends.-> A1
        X1[❌ Circular Detected]
    end
    
    subgraph "Indirect Circular - Recursive Detection"
        A2[Computed A]
        B2[Computed B]
        C2[Computed C]
        A2 -.Attempting to Depend.-> B2
        B2 -.Already Depends.-> C2
        C2 -.Already Depends.-> A2
        X2[❌ Circular Detected]
    end
    
    subgraph "Normal Dependency Chain - No Circular"
        A3[Computed A]
        B3[Computed B]
        C3[Computed C]
        D3[Signal D]
        A3 --> B3
        B3 --> C3
        C3 --> D3
        OK[✅ Safe]
    end
    
    style X1 fill:#f44336,color:#fff
    style X2 fill:#f44336,color:#fff
    style OK fill:#4CAF50,color:#fff
```

### 8.3 Circular Detection Sequence

```mermaid
sequenceDiagram
    participant User as User Code
    participant A as Computed A
    participant B as Computed B
    participant C as Computed C
    participant Check as Circular Detector
    
    Note over User,Check: === Attempting to Create Circular Dependency ===
    
    User->>A: computed(() => b() + 1)
    A->>B: Create Dependency Relationship
    Note over B: A Depends on B ✓
    
    User->>B: computed(() => c() + 1)
    B->>C: Create Dependency Relationship
    Note over C: B Depends on C ✓
    
    User->>C: computed(() => a() + 1)
    C->>Check: link(A, C)
    activate Check
    
    Check->>Check: Set A.flags |= RecursedCheck
    Check->>Check: Traverse C's deps
    
    Check->>B: Check B
    Note over B: B is Computed, Recursively Check
    
    Check->>Check: Traverse B's deps
    Check->>A: Check A
    
    Note over A: A.flags & RecursedCheck != 0<br/>Circular Found!
    
    Check->>Check: Clear RecursedCheck Flag
    Check-->>C: ❌ Throw Error: "Circular dependency"
    deactivate Check
    
    C-->>User: ❌ Error: Circular Dependency Detected
```

---

## 9. Complete Execution Flow

### 9.1 Shopping Cart Example Complete Flow

```mermaid
sequenceDiagram
    participant User as User Code
    participant Price as Signal: price
    participant Qty as Signal: quantity
    participant Total as Computed: total
    participant UI as Effect: updateUI
    participant Queue as Execution Queue
    
    Note over User,Queue: === Step 1: Initialization ===
    
    User->>Price: signal(100)
    Note over Price: value = 100
    
    User->>Qty: signal(2)
    Note over Qty: value = 2
    
    User->>Total: computed(() => price() * quantity())
    Note over Total: Not Computed, Awaiting First Access
    
    User->>UI: effect(() => print(total()))
    Note over UI: Create Effect
    
    UI->>Total: First Access total()
    activate Total
    Total->>Price: Access price()
    Price-->>Total: 100 (Establish Dependency)
    Total->>Qty: Access quantity()
    Qty-->>Total: 2 (Establish Dependency)
    Total->>Total: Calculate: 100 * 2 = 200
    Total-->>UI: 200 (Establish Dependency)
    deactivate Total
    
    UI->>UI: print("Total: 200")
    
    Note over User,Queue: === Step 2: Batch Update ===
    
    User->>User: startBatch()
    Note over Queue: batchDepth = 1
    
    User->>Price: price(150)
    Note over Price: value = 150
    Price->>Total: Mark Dirty
    Note over Total: flags |= Dirty
    Total->>UI: Mark Dirty + Queued
    Note over UI: flags |= Dirty | Queued
    UI->>Queue: Add to Queue
    
    User->>Qty: quantity(3)
    Note over Qty: value = 3
    Qty->>Total: Mark Dirty
    Note over Total: Already Dirty, Skip
    Total->>UI: Mark Dirty + Queued
    Note over UI: Already Queued, Skip
    
    User->>User: endBatch()
    Note over Queue: batchDepth = 0
    
    Queue->>UI: flush() - Run Effect
    activate UI
    UI->>Total: Read total()
    activate Total
    Note over Total: Detected Dirty<br/>Need to Recompute
    Total->>Price: Read price()
    Price-->>Total: 150
    Total->>Qty: Read quantity()
    Qty-->>Total: 3
    Total->>Total: Calculate: 150 * 3 = 450
    Total->>Total: Clear Dirty
    Total-->>UI: 450
    deactivate Total
    UI->>UI: print("Total: 450")
    UI->>UI: Clear Dirty + Queued
    deactivate UI
    
    Note over User,Queue: ✅ 2 Modifications, Only 1 Effect Execution
```

### 9.2 Complete Lifecycle State Machine

```mermaid
stateDiagram-v2
    [*] --> Created: Create Reactive Object
    
    Created --> Initialized: Set Initial Value
    
    Initialized --> Tracking: Start Dependency Tracking
    
    state Tracking {
        [*] --> CollectingDeps
        CollectingDeps --> Executing: Execute Function
        Executing --> AutoLinking: Access Dependencies
        AutoLinking --> Executing: Continue Execution
        Executing --> [*]: Complete
    }
    
    Tracking --> Active: Establish Dependency Relationships
    
    Active --> Dirty: Dependencies Change
    Dirty --> Checking: Check if Update Needed
    
    state Checking {
        [*] --> VerifyDeps
        VerifyDeps --> StillDirty: Update Actually Needed
        VerifyDeps --> FalseDirty: Dependencies Not Really Changed
        FalseDirty --> [*]: Clear Dirty
    }
    
    Checking --> Active: No Update Needed
    Checking --> Updating: Update Required
    
    state Updating {
        [*] --> ClearOldDeps
        ClearOldDeps --> Recompute
        Recompute --> TrackNewDeps
        TrackNewDeps --> UpdateCache
        UpdateCache --> [*]
    }
    
    Updating --> Active: Update Complete
    
    Active --> Stopping: Call stop()
    
    state Stopping {
        [*] --> PurgeDeps
        PurgeDeps --> ClearFromSubs
        ClearFromSubs --> ReleaseMemory
        ReleaseMemory --> [*]
    }
    
    Stopping --> [*]: Destroy
    
    note right of Tracking
        activeSub Set
        Automatic Dependency Collection
    end note
    
    note right of Checking
        Smart Dirty Checking
        Avoid Unnecessary Computation
    end note
    
    note right of Updating
        Clear Old Dependencies
        Re-track
        Update Cache
    end note
```

### 9.3 Multi-Level Dependency Propagation

```mermaid
graph TD
    Start([User Modifies Signal]) --> L0[Layer 0: Signal]
    
    L0 -->|Immediate Notify| L1A[Layer 1: Computed A]
    L0 -->|Immediate Notify| L1B[Layer 1: Computed B]
    L0 -->|Immediate Notify| L1C[Layer 1: Effect 1]
    
    L1A -->|Propagate| L2A[Layer 2: Computed C]
    L1A -->|Propagate| L2B[Layer 2: Effect 2]
    L1B -->|Propagate| L2C[Layer 2: Computed D]
    
    L2A -->|Propagate| L3A[Layer 3: Effect 3]
    L2C -->|Propagate| L3B[Layer 3: Effect 4]
    
    L1C -.Add to Queue.-> Queue[Execution Queue]
    L2B -.Add to Queue.-> Queue
    L3A -.Add to Queue.-> Queue
    L3B -.Add to Queue.-> Queue
    
    Queue --> Flush[flush Execute]
    Flush --> Execute[Execute by Layer Order]
    
    Execute --> End([Complete])
    
    style Start fill:#4CAF50
    style L0 fill:#4CAF50
    style L1A fill:#FFA726
    style L1B fill:#FFA726
    style L2A fill:#FF7043
    style L2C fill:#FF7043
    style L1C fill:#f44336,color:#fff
    style L2B fill:#f44336,color:#fff
    style L3A fill:#f44336,color:#fff
    style L3B fill:#f44336,color:#fff
    style Queue fill:#9C27B0
    style Flush fill:#FF9800
```

---

## 10. Performance Optimization Summary

### 10.1 Core Optimization Techniques

```mermaid
mindmap
    root((Alien Signals<br/>Performance))
        Data Structure Optimization
            Doubly Linked List
                O1 Dependency Operations
                Fast Insert/Delete
                No Need to Traverse
            Bitwise Flags
                Store Multiple States in Single Integer
                CPU Native Instructions
                Minimal Memory Access
        Algorithm Optimization
            Smart Dirty Checking
                Avoid Unnecessary Computation
                Recursively Verify Dependencies
                Fast Path Return
            Lazy Evaluation
                Compute Only When Needed
                Cache Computed Results
                Direct Return if Dependencies Unchanged
        Batch Updates
            Merge Multiple Modifications
            Reduce Effect Executions
            Nested Batch Support
        Memory Management
            Auto Cleanup Dependencies
            Prevent Memory Leaks
            Scope Batch Release
        Safety Mechanisms
            Circular Dependency Detection
            Recursive Depth Limit
            Timely Error Capture
```

### 10.2 Performance Metrics Comparison

```mermaid
graph LR
    subgraph Traditional Reactive Systems
        A1[Dependency Array - O n]
        A2[Full Diff - O n]
        A3[Multiple Effect Executions]
        A4[Manual Memory Cleanup]
    end
    
    subgraph Alien Signals
        B1[Doubly Linked List - O 1]
        B2[Smart Dirty Check - O 1]
        B3[Batch Deduplicated Execution]
        B4[Auto Memory Management]
    end
    
    A1 -.Inferior to.-> B1
    A2 -.Inferior to.-> B2
    A3 -.Inferior to.-> B3
    A4 -.Inferior to.-> B4
    
    style A1 fill:#FFCDD2
    style A2 fill:#FFCDD2
    style A3 fill:#FFCDD2
    style A4 fill:#FFCDD2
    style B1 fill:#C8E6C9
    style B2 fill:#C8E6C9
    style B3 fill:#C8E6C9
    style B4 fill:#C8E6C9
```

---

## 11. Summary

The Alien Signals reactive system achieves high performance through the following core technologies:

### 🎯 Core Features

1. **Doubly Linked List Dependency System** - O(1) time complexity for dependency operations
2. **Bitwise State Management** - Efficient flag operations
3. **Automatic Dependency Tracking** - Zero-configuration dependency collection
4. **Smart Dirty Checking** - Minimize unnecessary computation
5. **Batch Update Optimization** - Merge multiple modifications, reduce executions
6. **Lazy Evaluation Strategy** - Compute on-demand, cache results
7. **Circular Dependency Detection** - Ensure system stability
8. **Automatic Memory Management** - Prevent memory leaks

### 📊 Design Advantages

- ✅ **High Performance**: Key operations are O(1) time complexity
- ✅ **Easy to Use**: Automatic dependency tracking, no manual configuration needed
- ✅ **Extensible**: Clear three-layer architecture design
- ✅ **Memory Safe**: Automatic cleanup of unused dependencies
- ✅ **Type Safe**: Strict type marker system
- ✅ **Batch Optimized**: Support for nested batch updates

### 🔗 Related Documentation

- [WIKI Technical Deep Dive](WIKI.md)
- [WIKI Chinese Version](WIKI_CN.md)
- [Watch Feature Details](wiki_watch.md)
- [Watch Feature Summary](WIKI_WATCH_SUMMARY.md)

---

**Document Version**: v1.0  
**Last Updated**: 2025-10-17  
**Mermaid Version**: 10.0+  
**Applicable to**: alien-signals-in-lua v3.0.1
