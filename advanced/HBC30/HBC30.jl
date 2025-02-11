using Geant4
using Geant4.SystemOfUnits
using Printf, GeometryBasics
using CairoMakie, Rotations, LinearAlgebra, IGLWrap_jll  # to force loading G4Vis extension

include(joinpath(@__DIR__, "HBC30Detector.jl"))
hbc30 = HBC30()

##---Define Simulation Data struct------------------------------------------------------------------
struct Track
    particle::String
    charge::Int
    energy::Float64
    points::Vector{Point3{Float64}}
end
mutable struct HBC30SimData <: G4JLSimulationData
    ##---Run data-----------------------------------------------------------------------------------
    fParticle::String
    fEkin::Float64
    ##---trigger/veto-------------------------------------------------------------------------------
    veto::Bool
    ##---tracks-------------------------------------------------------------------------------------
    tracks::Vector{Track}
    HBC30SimData() = new("", 0.0, false, [])
end

##---Step action------------------------------------------------------------------------------------
function stepaction(step::G4Step, app::G4JLApplication)::Nothing
    tracks = getSIMdata(app).tracks
    p = step |> GetPostStepPoint |> GetPosition
    auxpoints = step |> GetPointerToVectorOfAuxiliaryPoints
    if auxpoints != C_NULL
        for ap in auxpoints
            push!(tracks[end].points, Point3{Float64}(x(ap),y(ap),z(ap)))
        end
    end
    push!(tracks[end].points, Point3{Float64}(x(p),y(p),z(p)))
    return
end
##---Tracking pre-action----------------------------------------------------------------------------
function pretrackaction(track::G4Track, app::G4JLApplication)::Nothing
    tracks = getSIMdata(app).tracks
    p = GetPosition(track)[]
    particle = track |> GetParticleDefinition
    name = particle |> GetParticleName |> String
    charge = particle |> GetPDGCharge |> Int
    energy = track |> GetKineticEnergy
    push!(tracks, Track(name, charge, energy, [Point3{Float64}(x(p),y(p),z(p))]))
    return
end
##---Tracking post-action----------------------------------------------------------------------------
function posttrackaction(track::G4Track, app::G4JLApplication)::Nothing
    data = getSIMdata(app)
    id = track |> GetTrackID
    energy = track |> GetKineticEnergy
    if id == 1 && energy > 0.80 * data.fEkin # primary particle did not losse any energy
        if track |> GetStep |> GetPostStepPoint |> GetPhysicalVolume == C_NULL  # Only if outside world
            data.veto = true
        end
    end
    return
end
##---Begin-event-action----------------------------------------------------------------------------
function beginevent(::G4Event, app::G4JLApplication)::Nothing
    data = getSIMdata(app)
    data.veto = false
    empty!(data.tracks)
    return
end
##---Begin Run Action-------------------------------------------------------------------------------
function beginrun(run::G4Run, app::G4JLApplication)::Nothing
    data = getSIMdata(app)
    gun = app.generator.data.gun
    data.fParticle = gun |> GetParticleDefinition |> GetParticleName |> String
    data.fEkin = gun |> GetParticleEnergy
    return
end;

import Geant4.SystemOfUnits:tesla
particlegun = G4JLGunGenerator(particle = "pi+",
                               energy = 330MeV,
                               direction = G4ThreeVector(0,-1,0),
                               position = G4ThreeVector(0, hbc30.worldZHalfLength,0));

bfield = G4JLUniformMagField(G4ThreeVector(0,0, 1.5tesla));

app = G4JLApplication(; detector = hbc30,                             # detector with parameters
                        simdata = HBC30SimData(),                     # simulation data structure
                        generator = particlegun,                      # primary particle generator
                        field = bfield,                               # uniform magnetic field
                        nthreads = 0,                                 # # of threads (0 = no MT)
                        physics_type = FTFP_BERT,                     # what physics list to instantiate
                        stepaction_method = stepaction,               # step action method
                        begineventaction_method = beginevent,         # begin-event action (initialize per-event data)
                        pretrackaction_method = pretrackaction,       # pre-tracking action
                        posttrackaction_method = posttrackaction,     # post-tracking action
                        beginrunaction_method = beginrun              # begin run action
                      );

# Draw detector
function drawdetector(s, app)
    world = GetWorldVolume()
    Geant4.draw!(s, world)
end
# Draw event
function drawevent(s, app)
    data = app.simdata[1]
    # clear previous plots from previous event
    tobe = [p for p in plots(s) if p isa Lines || p isa Makie.Text]  # The event is made of lines and text
    for p in tobe
        delete!(s,p)
    end
    # draw new event
    for t in data.tracks
        style = abs(t.charge) > 0. ? :solid : :dot
        lines!(s, t.points, linestyle=style)
        if t.energy > data.fEkin/20
            text!(s, t.points[end], text=t.particle)
        end
    end
end

# Very simplistic trigger to get interesting events to plot
function nexttrigger(app)
    data = app.simdata[1]
    beamOn(app,1)
    n = 1
    while data.veto
        beamOn(app,1)
        n += 1
    end
    println("Got a trigger after $n generated particles")
end;

configure(app)
initialize(app)

ui`/tracking/storeTrajectory 2` ## store auxiliary points to smooth the trajectory

fig = Figure(size=(2048,2028))
s = LScene(fig[1,1])

drawdetector(s, app)
nexttrigger(app); drawevent(s, app)

display(fig)

SetParticleEnergy(particlegun, 1GeV)
SetParticleByName(particlegun, "e-")

fig = Figure(size=(2048,2028))
s = LScene(fig[1,1])

drawdetector(s, app)
nexttrigger(app); drawevent(s, app)

display(fig)
