function check_present(ds, vars, filename)
    for name in vars
        haskey(ds, name) || error("Missing variable $name in $filename")
    end
    return nothing
end

function check_no_nan(ds, vars, filename)
    check_present(ds, vars, filename)
    for name in vars
        data = Array(ds[name])
        if any(x -> ismissing(x) || (x isa AbstractFloat && isnan(x)), data)
            error("Variable $name in $filename contains missing or NaN values")
        end
    end
    return nothing
end
