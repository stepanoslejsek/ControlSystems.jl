"""
A StateSpace model with a partioning imposed according to

A  | B1  B2
——— ————————
C1 | D11 D12
C2 | D21 D22

It corresponds to partioned input and output signals
u = [u1 u2]^T
y = [y1 y2]^T

"""
struct PartitionedStateSpace{TE<:TimeEvolution, S<:AbstractStateSpace{TE}} <: LTISystem{TE}
    P::S
    nu1::Int
    ny1::Int
end
# For converting between different S
PartitionedStateSpace{TE, S}(partsys::PartitionedStateSpace{TE}) where {TE, S<:StateSpace} =
    PartitionedStateSpace{TE, S}(S(partsys.P), partsys.nu1, partsys.ny1)

function PartitionedStateSpace(
    A,
    B1,
    B2,
    C1,
    C2,
    D11,
    D12,
    D21,
    D22,
    timeevol::TimeEvolution,
)
    nx = size(A, 1)
    nw = size(B1, 2)
    nu = size(B2, 2)
    nz = size(C1, 1)
    ny = size(C2, 1)

    size(A, 2) != nx && nx != 0 && error("A must be square")
    size(B1, 1)  == nx ||          error("B1 must have the same row size as A")
    size(B2, 1)  == nx ||          error("B2 must have the same row size as A")
    size(C1, 2)  == nx ||          error("C1 must have the same column size as A")
    size(C2, 2)  == nx ||          error("C2 must have the same column size as A")
    size(D11, 2) == nw ||          error("D11 must have the same column size as B1")
    size(D21, 2) == nw ||          error("D21 must have the same column size as B1")
    size(D12, 2) == nu ||          error("D12 must have the same column size as B2")
    size(D22, 2) == nu ||          error("D22 must have the same column size as B2")
    size(D11, 1) == nz ||          error("D11 must have the same row size as C1")
    size(D12, 1) == nz ||          error("D12 must have the same row size as C1")
    size(D21, 1) == ny ||          error("D21 must have the same row size as C2")
    size(D22, 1) == ny ||          error("D22 must have the same row size as C2")

    PartitionedStateSpace(ss(A, [B1 B2], [C1; C2], [D11 D12; D21 D22], timeevol), nw, nz)
end

function getproperty(sys::PartitionedStateSpace, d::Symbol)
    P = getfield(sys, :P)
    nu1 = getfield(sys, :nu1)
    ny1 = getfield(sys, :ny1)

    if d === :Ts
        return P.Ts # Will throw deprecation until removed # DEPRECATED
    elseif d === :P
        return P
    elseif d === :nu1
        return nu1
    elseif d === :ny1
        return ny1
    elseif d === :A
        return P.A
    elseif d === :B1
        return P.B[:, 1:nu1]
    elseif d === :B2
        return P.B[:, nu1+1:end]
    elseif d === :C1
        return P.C[1:ny1, :]
    elseif d === :C2
        return P.C[ny1+1:end, :]
    elseif d === :D11
        return P.D[1:ny1, 1:nu1]
    elseif d === :D12
        return P.D[1:ny1, nu1+1:end]
    elseif d === :D21
        return P.D[ny1+1:end, 1:nu1]
    elseif d === :D22
        return P.D[ny1+1:end, nu1+1:end]
    else
        return getproperty(P, d)
    end
end

function Base.propertynames(s::PartitionedStateSpace, private::Bool=false)
    (fieldnames(typeof(s))..., :A, :B, :C, :D, :B1, :B2, :C1, :C2, :D11, :D12, :D21, :D22, :nu, :ny, :nx, (isdiscrete(s) ? (:Ts,) : ())...)
end

timeevol(sys::PartitionedStateSpace) = timeevol(sys.P)

function +(s1::PartitionedStateSpace, s2::PartitionedStateSpace)
    timeevol = common_timeevol(s1,s2)

    A = blockdiag(s1.A, s2.A)

    B = [[s1.B1; s2.B1] blockdiag(s1.B2, s2.B2)]

    C = [[s1.C1 s2.C1];
    blockdiag(s1.C2, s2.C2)]

    D = [(s1.D11 + s2.D11) s1.D12 s2.D12;
    [s1.D21; s2.D21] blockdiag(s1.D22, s2.D22)]

    P = StateSpace(A, B, C, D, timeevol) # How to handle discrete?
    PartitionedStateSpace(P, s1.nu1 + s2.nu1, s1.ny1 + s2.ny1)
end





"""
    Series connection of partioned StateSpace systems.
"""
function *(s1::PartitionedStateSpace, s2::PartitionedStateSpace)
    timeevol = common_timeevol(s1,s2)

    A = [s1.A                           s1.B1*s2.C1;
    zeros(size(s2.A,1),size(s1.A,2))      s2.A]

    B = [s1.B1*s2.D11                         s1.B2           s1.B1*s2.D12;
    s2.B1              zeros(size(s2.B2,1),size(s1.B2,2))          s2.B2]

    C = [s1.C1                       s1.D11*s2.C1;
    s1.C2                        s1.D21*s2.C1;
    zeros(size(s2.C2,1),size(s1.C2,2))         s2.C2]

    D = [s1.D11*s2.D11           s1.D12        s1.D11*s2.D12;
    s1.D21*s2.D11           s1.D22        s1.D21*s2.D12;
    s2.D21          zeros(size(s2.D22,1),size(s1.D22,2))          s2.D22        ]

    P = StateSpace(A, B, C, D, timeevol)
    PartitionedStateSpace(P, s2.nu1, s1.ny1)
end



# QUESTION: What about algebraic loops and well-posedness?! Perhaps issue warning if P1(∞)*P2(∞) > 1
function feedback(s1::PartitionedStateSpace, s2::PartitionedStateSpace)
    timeevol = common_timeevol(s1,s2)
    X_11 = (I + s2.D11*s1.D11)\[-s2.D11*s1.C1  -s2.C1]
    X_21 = (I + s1.D11*s2.D11)\[s1.C1  -s1.D11*s2.C1]

    # For the case of two outputs
    #    X_12 = [I   -s2.D11   -s2.D11*s1.D12   -s2.D12]
    #    X_22 = [s1.D11  I     s1.D12          -s1.D11*s2.D12]
    X_12 = (I + s2.D11*s1.D11)\[I      -s2.D11*s1.D12   -s2.D12]
    X_22 = (I + s1.D11*s2.D11)\[s1.D11   s1.D12          -s1.D11*s2.D12]

    A = [s1.B1 * X_11 ; s2.B1 * X_21] + blockdiag(s1.A, s2.A)

    B = [s1.B1 * X_12 ; s2.B1 * X_22]
    tmp = blockdiag(s1.B2, s2.B2)
    B[:, end-size(tmp,2)+1:end] .+= tmp

    C = [s1.D11 * X_11 ;
         s1.D21 * X_11 ;
         s2.D21 * X_21 ] + [s1.C1 zeros(size(s1.C1,1),size(s2.C1,2)); blockdiag(s1.C2, s2.C2)]

    D = [s1.D11 * X_12 ;
        s1.D21 * X_12 ;
        s2.D21 * X_22 ]
    tmp = [s1.D12 zeros(size(s1.D12,1),size(s2.D12,2)); blockdiag(s1.D22, s2.D22)]
    D[:, end-size(tmp,2)+1:end] .+= tmp

    # in case it is desired to consider both outputs
    # C = [s1.D11 * X_11 ;
    #      s2.D11 * X_21 ;
    #      s1.D21 * X_11 ;
    #      s2.D21 * X_21 ] + [blockdiag(s1.C1, s2.C1); blockdiag(s1.C2, s2.C2)]
    #
    # D = [s1.D11 * X_12 ;
    #     s2.D11 * X_22 ;
    #     s1.D21 * X_12 ;
    #     s2.D21 * X_22 ]
    #tmp = [blockdiag(s1.D12, s2.D12); blockdiag(s1.D22, s2.D22)]
    #D[:, end-size(tmp,2)+1:end] .+= tmp

    P = StateSpace(A, B, C, D, timeevol)
    PartitionedStateSpace(P, s2.nu1, s1.ny1)
end

""" Concatenate systems vertically with
    same first input u1
    second input [u2_1; u2_2 ...]
    and output  y1 = [y1_1; y1_2, ...]
                y2 = [y2_1; y2_2, ...]
    for u1_i, u2_i, y1_i, y2_i, where i denotes system i
"""
function vcat_1(systems::PartitionedStateSpace...)
    # Perform checks
    timeevol = common_timeevol(systems...)

    nu1 = systems[1].nu1
    if !all(s.nu1 == nu1 for s in systems)
        error("All systems must have same first input dimension")
    end

    A = blockdiag([s.A for s in systems]...)

    B1 = reduce(vcat, [s.B1 for s in systems])
    B2 = blockdiag([s.B2 for s in systems]...)

    C1 = blockdiag([s.C1 for s in systems]...)
    C2 = blockdiag([s.C2 for s in systems]...)

    D11 = reduce(vcat, [s.D11 for s in systems])
    D12 = blockdiag([s.D12 for s in systems]...)
    D21 = reduce(vcat, [s.D21 for s in systems])
    D22 = blockdiag([s.D22 for s in systems]...)

    sysnew = StateSpace(A, [B1 B2], [C1; C2], [D11 D12; D21 D22], timeevol)
    return PartitionedStateSpace(sysnew, nu1, sum(s -> s.ny1, systems))
end


""" Concatenate systems horizontally with
    same first ouput y1 being the sum
    second output y2 = [y2_1; y2_2, ...]
    and inputs  u1 = [u1_1; u1_2, ...]
    u2 = [u2_1; u2_2, ...]
    for u1_i, u2_i, y1_i, y2_i, where i denotes system i
"""
function hcat_1(systems::PartitionedStateSpace...)
    # Perform checks
    timeevol = common_timeevol(systems...)

    ny1 = systems[1].ny1
    if !all(s.ny1 == ny1 for s in systems)
        error("All systems must have same first ouput dimension")
    end

    A = blockdiag([s.A for s in systems]...)

    B1 = blockdiag([s.B1 for s in systems]...)
    B2 = blockdiag([s.B2 for s in systems]...)

    C1 = reduce(hcat, [s.C1 for s in systems])
    C2 = blockdiag([s.C2 for s in systems]...)

    D11 = reduce(hcat, [s.D11 for s in systems])
    D12 = reduce(hcat, [s.D12 for s in systems])
    D21 = blockdiag([s.D21 for s in systems]...)
    D22 = blockdiag([s.D22 for s in systems]...)

    sysnew = StateSpace(A, [B1 B2], [C1; C2], [D11 D12; D21 D22], timeevol)
    return PartitionedStateSpace(sysnew, sum(s -> s.nu1, systems), ny1)
end

function Base.convert(::Type{<:PartitionedStateSpace}, sys::T) where T<: StateSpace
    PartitionedStateSpace(sys,sys.nu,sys.ny)
end

# Test equality (of realizations)
function ==(sys1::PartitionedStateSpace, sys2::PartitionedStateSpace)
    all(getfield(sys1, f) == getfield(sys2, f) for f in fieldnames(PartitionedStateSpace))
end
