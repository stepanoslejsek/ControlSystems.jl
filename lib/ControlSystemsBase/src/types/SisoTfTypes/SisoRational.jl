## User should just use TransferFunction
struct SisoRational{T} <: SisoTf{T}
    num::Polynomial{T, :x}
    den::Polynomial{T, :x}
    function SisoRational{T}(num::Polynomial{T, S}, den::Polynomial{T, S}) where {T <: Number, S}
        if isequal(den, zero(den))
            error("Cannot create SisoRational with zero denominator")
        elseif isequal(num, zero(num))
            # The numerator is zero, make the denominator 1
            den = one(den)
        end
        T <: AbstractFloat && length(den) > 20 && eps(T) >= eps(Float64) && @warn "High-order transfer functions are highly sensitive to numerical errors. The result may be inaccurate. Consider making use of statespace systems instead" maxlog=1
        new{T}(num, den)
    end
end
function SisoRational(num::Polynomial{T1}, den::Polynomial{T2}) where T1 <: Number where T2 <: Number
    T = promote_type(T1,T2)
    SisoRational{T}(Polynomial{T, :x}(num.coeffs), Polynomial{T, :x}(den.coeffs))
end
SisoRational{T}(num::Polynomial, den::Polynomial) where T = SisoRational{T}(convert(Polynomial{T, :x}, num), convert(Polynomial{T, :x}, den))

function SisoRational{T}(num::AbstractVector, den::AbstractVector) where T <: Number # NOTE: Typearguemnts on the parameters?
    SisoRational{T}(Polynomial{T, :x}(reverse(num)), Polynomial{T, :x}(reverse(den)))
end
function SisoRational(num::AbstractVector{T1}, den::AbstractVector{T2}) where T1 <: Number where T2 <: Number
    T = promote_type(T1,T2)
    SisoRational{T}(num, den)
end
# NOTE: How many of these above are actually needed?
# TODO: Add method for scalar inputs


Base.zero(::Type{SisoRational{T}}) where T = SisoRational{T}([zero(T)], [one(T)])
Base.one(::Type{SisoRational{T}}) where T = SisoRational{T}([one(T)], [one(T)])

Base.one(f::SisoRational) = one(typeof(f))
Base.zero(f::SisoRational) = zero(typeof(f))

isproper(f::SisoRational) = (length(f.num) <= length(f.den))

function minreal(sys::SisoRational{T}, eps::Real=sqrt(eps())) where T
    T2 = typeof(zero(T)/one(T))
    return convert(SisoRational{T2}, minreal(convert(SisoZpk,sys), eps))
end

function print_siso(io::IO, f::SisoRational, var=:s)
    # Convert the numerator and denominator to strings
    numstr = sprint(printpolyfun(var), f.num)
    denstr = sprint(printpolyfun(var), f.den)

    # Figure out the length of the separating line
    len_num = length(numstr)
    len_den = length(denstr)
    dashcount = max(len_num, len_den)

    # Center the numerator or denominator
    if len_num < dashcount
        numstr = "$(repeat(" ", div(dashcount - len_num, 2)))$numstr"
    else
        denstr = "$(repeat(" ", div(dashcount - len_den, 2)))$denstr"
    end
    println(io, numstr)
    println(io, repeat("-", dashcount))
    println(io, denstr)
end

numvec(f::SisoRational) = reverse(coeffs(f.num))
denvec(f::SisoRational) = reverse(coeffs(f.den))

denpoly(f::SisoRational) = f.den
numpoly(f::SisoRational) = f.num

tzeros(f::SisoRational) = roots(f.num)
poles(f::SisoRational) = roots(f.den)

function evalfr(f::SisoRational{T}, s::Number) where T
    S = promote_op(/, promote_type(T, typeof(s)), promote_type(T, typeof(s)))
    den = f.den(s)
    if isequal(den, zero(S))
        convert(S,Inf)
    else
        f.num(s)/den
    end
end

function ==(f1::SisoRational, f2::SisoRational)
    # Get representation of num/den so index access is correct
    f1num, f1den = numvec(f1), denvec(f1)
    f2num, f2den = numvec(f2), denvec(f2)
    (f1num * f2den[1] == f2num * f1den[1] && f1den * f2den[1] == f2den * f1den[1]) # NOTE: Not in analogy with how it's done for SisoZpk
end

# We might want to consider alowing scaled num and den as equal
function isapprox(f1::SisoRational, f2::SisoRational; rtol::Real=sqrt(eps()), atol::Real=0)
    # Get representation of num/den so index access is correct
    f1num, f1den = numvec(f1), denvec(f1)
    f2num, f2den = numvec(f2), denvec(f2)
    if length(f1num) < length(f2num)
        f1num = [zeros(length(f2num) - length(f1num)); f1num]
    elseif length(f2num) < length(f1num)
        f2num = [zeros(length(f1num) - length(f2num)); f2num]
    end
    if length(f1den) < length(f2den)
        f1den = [zeros(length(f2den) - length(f1den)); f1den]
    elseif length(f2den) < length(f1den)
        f2den = [zeros(length(f1den) - length(f2den)); f2den]
    end
    isapprox(f1num * f2den[1], f2num * f1den[1], rtol=rtol, atol=atol) && isapprox(f1den * f2den[1], f2den * f1den[1], rtol=rtol, atol=atol)
end

+(f1::SisoRational, f2::SisoRational) = SisoRational(f1.num*f2.den + f2.num*f1.den, f1.den*f2.den)
+(f::SisoRational, n::Number) = SisoRational(f.num + n*f.den, f.den)
+(n::Number, f::SisoRational) = f + n
#.+(f::SisoRational, n::Number) = t + n
#.+(n::Number, f::SisoRational) = t + n

-(f1::SisoRational, f2::SisoRational) = SisoRational(f1.num*f2.den - f2.num*f1.den, f1.den*f2.den)
-(n::Number, f::SisoRational) = SisoRational(n*f.den - f.num, f.den)
-(f::SisoRational, n::Number) = +(f, -n)
#.-(f::SisoRational, n::Number) = -(t, n)
#.-(n::Number, f::SisoRational) = -(n, t)

-(f::SisoRational) = SisoRational((-f.num)::typeof(f.num), f.den) # typeassert due to https://github.com/JuliaMath/Polynomials.jl/issues/395 and can be removed once that is closed

# We overload this method to circumvent the Base methods use of promote_op(matprod,...)
function (*)(A::AbstractMatrix{<:SisoRational}, B::AbstractMatrix{<:SisoRational})
    # TS = promote_op(LinearAlgebra.matprod, eltype(A), eltype(B)) # TODO; this promote_op does not work 100% and often returns ControlSystemsBase.SisoRational{_A} where _A even though it should be ControlSystemsBase.SisoRational{eltype(A)}
    TS = promote_type(eltype(A), eltype(B))
    mul!(similar(B, TS, (size(A,1), size(B,2))), A, B)
end
*(f1::SisoRational, f2::SisoRational) = SisoRational(f1.num*f2.num, f1.den*f2.den)
*(f::SisoRational, n::Number) = SisoRational(f.num*n, f.den)
*(n::Number, f::SisoRational) = *(f, n)
#.*(f1::SisoRational, f2::SisoRational) = *(f1, f2)
#.*(f::SisoRational, n::Number) = *(f, n)
#.*(n::Number, f::SisoRational) = *(f, n)

/(n::Number, f::SisoRational) = SisoRational(n*f.den, f.num)
/(f::SisoRational, n::Number) = f*(1/n)
/(f1::SisoRational, f2::SisoRational) = f1*(1/f2)
