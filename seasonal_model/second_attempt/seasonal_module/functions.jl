using Parameters, StaticArrays, AxisArrays, Plots, DifferentialEquations, Test


"""
    GrowingSeason(State0::SVector, param::Compact1Strain, t::Real)

This is the function to enter in ODEProblem from DifferentialEquations.jl. 
	
For a compact model, it returns the ODE associated to the growing season.
"""
function GrowingSeason(State0::SVector,
    param::Compact1Strain,
    t::Real)
    S, I = State0
    @unpack α, β = param

    dS = -β * S * I
    dI = +β * S * I - α * I

    @SVector [dS, dI]
end

"""
    GrowingSeason(State0::SVector, param::Compact1Strain, t::Real)

This is the function to enter in ODEProblem from DifferentialEquations.jl. 
	
For an elaborate model, it returns the ODE associated to the growing season.
"""
function GrowingSeason(State0::SVector,
						param::ParamAirborneElaborate1Strain,
						t::Real)

	P, S, I = State0
	@unpack α, β, Λ, Θ = param
	
	dP = - Λ * P
	dS = - Θ * P * S - β * S * I
	dI = + Θ * P * S + β * S * I - α * I

	@SVector [dP, dS, dI]
end


"""
    function WinterSeason(State0::SVector, param::Elaborate1Strain, t::Real)

This is the function to enter in ODEProblem from DifferentialEquations.jl. 
	
It only exists for elaborate models, and it returns the ODE associated to the winter season.
"""
function WinterSeason(State0::SVector,
					  param::Elaborate1Strain,
					  t::Real)
	P, S, I =  State0
	@unpack μ = param
	dP = -μ * P
	dS = 0
	dI = 0
	@SVector [dP, dS, dI]
end

"""
    growing(sp::StateParam0, param::Param; tp::TimeParam=TimeParam())

Simulates the growing season for any model, using ODEProblem from DifferentialEquations.jl.

It returns a vector of vectors that contains the simulation for a season, and also the last values of the simulation.
"""
function growing(sp::StateParam0,
				param::Param;
				tp::TimeParam=TimeParam())

	# simulation
	@unpack tspang, Δt = tp	
	prob = ODEProblem(GrowingSeason, sp.State0, tspang, param, saveat = Δt)
	sol  = solve(prob)

	# collect of last values
	res_end = last(sol)

	# build of results matrix
	res = []
	push!(res, sol.t)
	for i in 1:param.statelength
		# sol[i,:] = [...]
		push!(res, sol[i,:])
	end
	# res = [ [...], [...], ...]
	return res, res_end
end

"""
    winter(res_end,	param::Elaborate1Strain; tp::TimeParam=TimeParam())

Compute new initial conditions from the last values of the previous growing season.
Then it simulates the winter season for elaborate 1 strain models, using ODEProblem from DifferentialEquations.jl.

It returns a vector of vectors that contains the simulation, and the last values of the simulation.
"""
function winter(res_end,
				param::Elaborate1Strain;
				tp::TimeParam=TimeParam())

	# compute new CI
	Pend, Send, Iend = res_end
	@unpack Π = param
	sp = StateElaborate(P0=Pend + Π*Iend, S0=0, I0=0)

	# simulation
	@unpack tspanw, Δt = tp
	prob = ODEProblem(WinterSeason, sp.State0, tspanw, param, saveat = Δt)
	sol  = solve(prob)

	# collect of last values
	res_end = last(sol)

	# build of results matrix
	res = []
	push!(res, sol.t)
	for i in 1:param.statelength
		# sol[i,:] = [...]
		push!(res, sol[i,:])
	end
	# res = [ [...], [...], ...]
	return res, res_end
end

"""
    yeartransition(res_end,	param::ParamSoilborneCompact1Strain; tp::TimeParam=TimeParam())

Compute new initial conditions from the last values of growing season simulation.

It returns a StateCompact object.
"""
function yeartransition(res_end,
						param::ParamSoilborneCompact1Strain;
						tp::TimeParam=TimeParam())
	Send, Iend = res_end

	@unpack θ, Π, μ, λ, n = param
	@unpack T, τ = tp

	Snew = n * exp(-θ*Π*exp(-μ*(T-τ))/λ * Iend)
	Inew = n - Snew
	return StateCompact(S0=Snew, I0=Inew)
end

"""
    yeartransition(res_end,	param::ParamAirborneElaborate1Strain; tp::TimeParam=TimeParam())

Compute new initial conditions from the last values of winter season simulation.

It returns a StateElaborate object.
"""
function yeartransition(res_end,
						param::ParamAirborneElaborate1Strain;
						tp::TimeParam=TimeParam())
	Pend, Send, Iend = res_end
	@unpack n = param
	return StateElaborate(P0=Pend, S0=n ,I0=0)
end

"""
    simule(sp::StateParam0,	param::Param; tp::TimeParam=TimeParam())

Simule a year for any model.

It returns a vector of vectors that contains one year of simulation, and also the last values of the simulation.
"""
function simule(sp::StateParam0,
				param::Param;
				tp::TimeParam=TimeParam())

	# simule growing and collect data as a vector of vectors
	res, res_end = growing(sp, param, tp=tp)	
	
	# if elaborate model: compute new CI and simule winter
	if param.isElaborate
		resw, res_end = winter(res_end, param, tp=tp)
		# add result to the growing simulation
		for i in eachindex(res)
			res[i] = vcat(res[i], resw[i])
		end
	end

	# compute new CI for growing season
	CI = yeartransition(res_end, param, tp=tp)
	
	return res, CI
end

"""
    fill_mat(nyears::Int64,	sp::StateParam0, param::Param; tp::TimeParam=TimeParam())

Construct an empty named matrix to stock nyears of simulation.

Labels are filled automatically.
"""
function fill_mat(nyears::Int64,
					sp::StateParam0,
					param::Param;
					tp::TimeParam=TimeParam())
	
	@unpack T, τ, Δt = tp

	# autofill axis
	years = Symbol.(["annee$i" for i in 1:nyears])
	col = [:time]
	for i in 1:length(fieldnames(typeof(sp)))-1
		push!(col, fieldnames(typeof(sp))[i])
	end
	
	# creat undef matrix
	mat = Matrix{Vector{Float64}}(undef, nyears, length(sp.State0)+1)
	
	return AxisArray(mat, Axis{:lignes}(years), Axis{:colonnes}(col))
end

"""
    simule(nyears::Int64, sp::StateParam0, param::Param; tp::TimeParam=TimeParam())

Simule n years for any model.

It returns a named matrix that contains n years of simulation.
"""
function simule(nyears::Int64,
				sp::StateParam0,
				param::Param;
				tp::TimeParam=TimeParam())
	
	@test param.statelength==length(sp.State0)
	
	@unpack T, Δt = tp
	mat_res =  fill_mat(nyears, sp, param, tp=tp)

	CI = sp
	for i in 1:nyears
		res, CI = simule(CI, param, tp=tp)
		
		mat_res[i,:] = res
		mat_res[i,1] = mat_res[i,1] .+ (i-1)*T
	end
	
	return mat_res
end

"""
    isWinter_vect(t,tp)

From a time vector, returns a new vector of 0 and 1 for growing and winter saeson.
"""
isWinter_vect(t,tp) =[mod(x, 1) < tp.τ/tp.T ? 0 : 1 for x in t]

"""
    isWinter(t,tp)

From a matrix (only the time column or the entire matrix en simulation), returns a new matrix of 0 and 1 for growing and winter saeson.
"""
isWinter(t,tp) = [isWinter_vect(x,tp) for x in t[:,1]]

"""
    Plots.plot(nyears::Int64, sp::StateCompact,	param::Compact1Strain; tp::TimeParam=TimeParam())

Make a simulation of n years for a Compact 1 strain model.
Plot the solutions of this simulation.
"""
function Plots.plot(nyears::Int64,
					sp::StateCompact,
					param::Compact1Strain;
					tp::TimeParam=TimeParam())
	mat_res = simule(nyears, sp, param, tp=tp)
	
	simuleTime = 0:tp.Δt/nyears:nyears
	
	# convert days into years
	t = mat_res[:,1] ./365 
	
    # plot S
    p1 = plot(t, mat_res[:,2],
        label=false,
        xlims=[0, nyears],
        ylims=[0, param.n],
        ylabel="\$S\$",
        c=:black)
	p1 = plot!(simuleTime, isWinter_vect(simuleTime,tp)
			, fillrange = 0, fillcolor = :lightgray, fillalpha = 0.65, lw = 0, label="winter")

    # plot I
    p2 = plot(t, mat_res[:,3],
        label=false,
        xlims=[0, nyears],
        ylims=[0, param.n / 3],
        xlabel="Years",
        ylabel="\$I\$",
        c=:black)
	p2 = plot!(simuleTime, isWinter_vect(simuleTime,tp)
			, fillrange = 0, fillcolor = :lightgray, fillalpha = 0.65, lw = 0, label="winter")
	
    # plot S et I dans une même fenêtre
    plot(p1, p2,
        layout=(2, 1))
    title!("Simulation du modèle airborne compacte", subplot=1)

end

"""
    Plots.plot(nyears::Int64, sp::StateElaborate,	param::Elaborate1Strain; tp::TimeParam=TimeParam())

Make a simulation of n years for an elaborate 1 strain model.
Plot the solutions of this simulation.
"""
function Plots.plot(nyears::Int64,
					sp::StateElaborate,
					param::Elaborate1Strain;
					tp::TimeParam=TimeParam())
	mat_res = simule(nyears, sp, param, tp=tp)

	# convert days into years
	t = mat_res[:,1] ./365 

	
    # plot S
    p1 = plot(t, mat_res[:,3],
        label=false, ylabel="\$S\$",
        xlims=[0, nyears], ylims=[0, param.n],
        c=:black, linestyle=:solid)
	p1 = plot!(t, isWinter(t,tp), fillrange = 0, fillcolor = :lightgray, fillalpha = 0.65, lw = 0, label=false, legend=:topright)

    # plot I
    p2 = plot(t, mat_res[:,4],
        label=false, xlabel="Years", ylabel="\$I\$",
        xlims=[0, nyears], ylims=[0, param.n / 3],
        c=:black, linestyle=:solid)
	# plot P
    p2 = plot!(twinx(),t, mat_res[:,2],
        label=false, ylabel="\$P\$",
        xlims=[0, nyears], ylims=[0, param.n / 3],
		c=:black, linestyle=:dashdotdot)
	p2 = plot!(t, isWinter(t,tp), fillrange = 0, fillcolor = :lightgray, fillalpha = 0.65, lw = 0, label=false, legend=:topright)
	
    # plot S et I dans une même fenêtre
    plot(p1, p2,
        layout=(2, 1))
    title!("Simulation du modèle soilborne élaboré", subplot=1)

end

"""
    affiche(nyears::Int64, sp::StateParam0, param::Param; tp::TimeParam=TimeParam())

Make a simulation of n years for any model.
Plot the solutions of this simulation.
"""
function affiche(nyears::Int64,
					sp::StateParam0,
					param::Param;
					tp::TimeParam=TimeParam())
	# simule
	mat = simule(nyears, sp, param)
	
	simuleTime = 0:tp.Δt/nyears:nyears

	# plot S0
	p1 = plot(mat[:,1] ./365, mat[:,:S0]
				, label=false
				, c=:black, linestyle=:solid)
	# add stripes
	p1 = plot!(simuleTime, isWinter_vect(simuleTime,tp), fillrange = 0, fillcolor = :lightgray, fillalpha = 0.65, lw = 0, label="winter")
	
	# plot everything else
	p2 = plot()
	for i in 2:size(mat)[2]
		if mat[:,i] != mat[:,:S0]
			p2 = plot!(mat[:,1] ./365, mat[:,i]
					#, label = String(fieldnames(typeof(sp))[i-1]))
					, label=false
					, ylims=[0, param.n/3]
					, c=:black, linestyle=:solid)
		end
	end
	# add stripes
	p2 = plot!(simuleTime, isWinter_vect(simuleTime,tp)
			, fillrange = 0, fillcolor = :lightgray, fillalpha = 0.65, lw = 0, label="winter")
	# plot S and everything else in two subplots
	plot(p1, p2,
        layout=(2, 1))
end