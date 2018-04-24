__precompile__()
#Todo:
#docs
#pretty print output by overloading show
#plotting via timeseries
#marketdata
#alternative error distributions
#standard errors
#demean?

#write fit!
#should archmodel carry ht?
# don't pass data into start
#figure out what to do about unid'd models. Eg, in fit, we had
#without ARCH terms, volatility is constant and beta_i is not identified.
#q == 0 && return ARCHModel(G, data, Tuple([mean(data.^2); zeros(T, p)]))

module ARCH

using StatsBase: StatisticalModel
using Optim
using Base.Cartesian: @nloops, @nref, @ntuple
import StatsBase: loglikelihood, nobs, fit, aic, bic, aicc, dof, coef, coefnames
export            loglikelihood, nobs, fit, aic, bic, aicc, dof, coef, coefnames
export ARCHModel, VolatilitySpec, simulate, selectmodel

abstract type VolatilitySpec end

struct ARCHModel{VS<:VolatilitySpec, T<:AbstractFloat} <: StatisticalModel
    data::Vector{T}
    coefs::Vector{T}
    ARCHModel{VS, T}(data, coefs) where {VS, T} = new(data, coefs)
end
ARCHModel(spec::Type{VS}, data::Vector{T}, coefs::Vector{T}) where {VS<:VolatilitySpec, T} = ARCHModel{VS, T}(data, coefs)

loglikelihood(am::ARCHModel{VS}) where {VS<:VolatilitySpec} = loglik!(zeros(am.data), VS, am.data, am.coefs)
nobs(am::ARCHModel) = length(am.data)
dof(am::ARCHModel{VS}) where {VS<:VolatilitySpec} = nparams(VS)
coef(am::ARCHModel)=am.coefs

fit(AM::Type{ARCHModel{VS}}, data) where {VS<:VolatilitySpec} = fit(T, data)
coefnames(::ARCHModel{VS}) where {VS<:VolatilitySpec} = coefnames(VS)

function simulate(spec::Type{VS}, nobs, coefs::Vector{T}) where {VS<:VolatilitySpec, T<:AbstractFloat}
    const warmup = 100
    data = zeros(T, nobs+warmup)
    ht = zeros(T, nobs+warmup)
    sim!(ht, spec, data, coefs)
    data[warmup+1:warmup+nobs]
end

function loglik!(ht::Vector{T1}, spec::Type{VS}, data::Vector{T1}, coefs::Vector{T1}) where {VS<:VolatilitySpec, T1<:AbstractFloat}
    T = length(data)
    r = presample(spec)
    length(coefs) == nparams(spec) || error("Incorrect number of parameters: expected $(p+q+1), got $(length(coefs)).")
    T > r || error("Sample too small.")
    log2pi = T1(1.837877066409345483560659472811235279722794947275566825634303080965531391854519)
    @inbounds begin
        h0 = uncond(spec, coefs)
        h0 > 0 || return T1(NaN)
        lh0 = log(h0)
        ht[1:r] .= h0
        LL = r*lh0+sum(data[1:r].^2)/h0
        @fastmath for t = r+1:T
            update!(ht, spec, data, coefs, t)
            LL += log(ht[t]) + data[t]^2/ht[t]
        end#for
    end#inbounds
    LL = -(T*log2pi+LL)/2
end#function


function sim!(ht::Vector{T1}, spec::Type{VS}, data::Vector{T1}, coefs::Vector{T1}) where {VS<:VolatilitySpec, T1<:AbstractFloat}
    T =  length(data)
    r = presample(spec)
    length(coefs) == nparams(spec) || error("Incorrect number of parameters: expected $(p+q+1), got $(length(coefs)).")
    @inbounds begin
        h0 = uncond(spec, coefs)
        h0 > 0 || error("Model is nonstationary.")
        randn!(@view data[1:r])
        data[1:r] .*= sqrt(h0)
        @fastmath for t = r+1:T
            update!(ht, spec, data, coefs, t)
            data[t] = sqrt(ht[t])*randn(T1)
        end
    end
    return nothing
end

function fit(spec::Type{VS}, data, algorithm=BFGS; kwargs...) where {VS<:VolatilitySpec}
    ht = zeros(data)
    obj = x -> -loglik!(ht, spec, data, x)
    x0 = startingvals(spec, data)
    lower, upper = constraints(spec, data)
    res = optimize(obj, x0, lower, upper, Fminbox{algorithm}(); kwargs...)
    return ARCHModel(spec, data, res.minimizer)
end

function selectmodel(spec::Type{VS}, data::Vector{T}, maxpq=3, args...; criterion=bic, kwargs...) where {VS<:VolatilitySpec, T<:AbstractFloat}
    ndims = length(Base.unwrap_unionall(spec).parameters) #e.g., two (p and q) for GARCH{p, q}
    res = _selectmodel(VS, Val{ndims}(), Val{maxpq}(), data)
    crits = criterion.(res)
    _, ind = findmin(crits)
    return res[ind]
end

@generated function _selectmodel(VS, ::Val{ndims}, ::Val{maxpq}, data) where {ndims, maxpq}
    quote
        res =Array{ARCHModel, $ndims}(@ntuple($ndims, i->$maxpq))
        @nloops $ndims i res begin
        @nref($ndims, res, i) = fit(VS{@ntuple($ndims, i)...}, data)
    end
    return res
end
end
include("GARCH.jl")
end#module
