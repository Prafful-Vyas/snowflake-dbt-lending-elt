select
    trim(counterparty_id)                       as counterparty_id,
    trim(legal_name)                            as legal_name,
    trim(sector)                                as sector,
    upper(trim(country))                        as country,
    upper(trim(internal_rating))                as internal_rating,
    cast(tax_id as {{ dbt.type_string() }})     as tax_id,
    cast(updated_at as timestamp)               as updated_at
from {{ source('raw', 'raw_counterparties') }}
