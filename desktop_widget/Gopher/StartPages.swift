// StartPages — pages built into the browser, at about:gemini and about:ftp: a way in to
// Geminispace and to the anonymous FTP archives that are still open, written as gemtext so
// they show like any Gemini page. Every place on them answered when they were written
// (November 2026); servers come and go, so a dead one is no sign the browser is broken.

import Foundation

enum StartPages {
    static func has(_ name: String) -> Bool { pages[name] != nil }

    static func title(_ name: String) -> String { pages[name]?.title ?? name }

    static func text(_ name: String) -> String { pages[name]?.text ?? "" }

    private static let pages: [String: (title: String, text: String)] = [
        "gemini": ("Geminispace", gemini),
        "ftp": ("Anonymous FTP", ftp),
    ]

    private static let gemini = """
        # Geminispace

        Gemini is a small protocol from 2019: pages of plain text, with links one to a line, sent over an encrypted connection and nothing else. No scripts, no styles, no cookies, no tracking. It sits between gopher, whose plainness it shares, and the web, whose links and encryption it keeps. These are good places to begin.

        ## Finding things

        => gemini://kennedy.gemi.dev/search Kennedy, a search engine for Geminispace
        => gemini://cosmos.skyjake.fi/ Cosmos, the newest posts from gemlogs everywhere
        => gemini://kennedy.gemi.dev/archive/ Delorean, a time machine for capsules that have changed or gone

        ## People

        => gemini://bbs.geminispace.org/ Bubble, a bulletin board with subspaces for every interest
        => gemini://station.martinrue.com/ Station, a small social site
        => gemini://midnight.pub/ Midnight Pub, a quiet virtual pub for short posts
        => gemini://smol.pub/ Smol Pub, a tiny blogging service

        ## Reading

        => gemini://gemi.dev/cgi-bin/wp.cgi/ Gemipedia, Wikipedia as gemtext
        => gemini://gemi.dev/cgi-bin/waffle.cgi/ NewsWaffle, news websites read through Gemini
        => gemini://gemi.dev/cgi-bin/chilly.cgi/ Chilly Weather, the forecast
        => gemini://gemi.dev/ gemi.dev, the capsule behind those three, with much more

        ## Homes

        Shared Unix systems where members keep a capsule, much as they keep a gopher hole.

        => gemini://sdf.org/ SDF Public Access UNIX System
        => gemini://tilde.team/ tilde.team
        => gemini://tilde.club/ tilde.club
        => gemini://envs.net/ envs.net
        => gemini://flounder.online/ Flounder, free hosting for a capsule of your own
        => gemini://capsule.town/ capsule.town

        ## Gemini itself

        => gemini://geminiprotocol.net/ Project Gemini
        => gemini://geminiprotocol.net/docs/faq.gmi The FAQ
        => gemini://geminiprotocol.net/docs/protocol-specification.gmi The protocol
        => gemini://geminiprotocol.net/docs/gemtext.gmi Gemtext, the page format
        => gemini://geminiprotocol.net/software/ Software for Gemini

        ## Elsewhere in this browser

        => about:ftp Anonymous FTP, the archives that are still open
        => gopher://sdf.org/ SDF's gopherspace
        => spartan://mozz.us/ Spartan, Gemini's plain-TCP cousin
        """

    private static let ftp = """
        # Anonymous FTP

        FTP is older than TCP/IP: it was first written down in 1971 (RFC 114), and the version still in use became the standard in 1985 (RFC 959). Before the web, it was how software and papers moved around: you logged in as "anonymous", changed into /pub, and fetched what you came for. Most archives have since moved to the web, but a good number still keep the door open.

        Folders open as lists here. Text files and pictures open in the window, and anything else is saved to disk. Gopher Browser only logs in anonymously, as FTP sends passwords unencrypted.

        ## Free software

        => ftp://ftp.gnu.org/gnu/ GNU, every package the project has released
        => ftp://ftp.netbsd.org/pub/NetBSD/ NetBSD
        => ftp://ftp.freebsd.org/pub/FreeBSD/ FreeBSD
        => ftp://ftp.slackware.com/pub/slackware/ Slackware, the oldest Linux distribution still going, back to release 3.3
        => ftp://ftp.isc.org/isc/ ISC, the home of BIND and the DHCP server

        ## The great archives

        => ftp://ftp.funet.fi/pub/ FUNET, the Finnish university network, where Linux was first uploaded in 1991
        => ftp://ftp.ibiblio.org/pub/ ibiblio, once sunsite.unc.edu, one of the oldest archives on the net
        => ftp://ftp.icm.edu.pl/pub/ ICM, at the University of Warsaw
        => ftp://ftp.halifax.rwth-aachen.de/ RWTH Aachen, mirrors of nearly every Linux distribution

        ## Old computers

        => ftp://ftp.aminet.net/ Aminet, Amiga software since 1992
        => ftp://ftp.apple.asimov.net/pub/apple_II/ Asimov, the Apple II archive
        => ftp://ftp.pigwa.net/stuff/ Pigwa, for the Atari 8-bit computers
        => ftp://ftp.oldskool.org/pub/ The Oldskool PC, old IBM PCs and compatibles, with a mirror of SimTel
        => ftp://ftp.scene.org/pub/ scene.org, the demoscene's archive

        ## Documents

        => ftp://ftp.funet.fi/rfc/ Every RFC, all forty thousand files of them
        => ftp://ftp.funet.fi/rfc/rfc959.txt RFC 959, the File Transfer Protocol itself
        => ftp://ftp.sdf.org/pub/ SDF's public archive

        ## Science

        => ftp://ftp.ncbi.nlm.nih.gov/ NCBI, the US National Center for Biotechnology Information: GenBank, PubMed and more
        => ftp://ftp.ebi.ac.uk/pub/ EMBL-EBI, the European Bioinformatics Institute
        => ftp://ftp.ripe.net/ripe/ RIPE NCC, the records of Europe's internet addresses

        ## Elsewhere in this browser

        => about:gemini Geminispace
        => gopher://sdf.org/ SDF's gopherspace
        """
}
