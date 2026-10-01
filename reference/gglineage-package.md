# gglineage: Machine-Readable Lineage IDs for 'ggplot2' Graphics

Stamp 'ggplot2' plots with an ID that can be read back out of the
pixels, so a stray screenshot of a chart can be traced to the analysis
run that made it. A faint dot code along the bottom margin carries
either a short text ID or a complete 128-bit UUID (RFC 9562
[doi:10.17487/RFC9562](https://doi.org/10.17487/RFC9562) ), survives
screenshots, JPEG compression and rescaling within measured limits, and
is protected by a 32-bit check so a decode is either exact or rejected.
The ID is the key to a record the user keeps, such as a manifest of
saved plots; provenance fields can also be embedded in PNG metadata.
Visible text stamps ("DRAFT", "CONFIDENTIAL") are included. Watermarks
are ordinary plot components added with '+', and never alter scales,
coordinates or facets.

## See also

Useful links:

- <https://github.com/despresj/gglineage>

- <https://despresj.github.io/gglineage/>

- Report bugs at <https://github.com/despresj/gglineage/issues>

## Author

**Maintainer**: Joe Despres <joe.r.despres@gmail.com> \[copyright
holder\]

Authors:

- Joe Despres <joe.r.despres@gmail.com> \[copyright holder\]
