"""Lazy exports keep lightweight database operations independent of ML imports."""

__all__ = ["MVA2Runner", "JITVideoPipeline", "SpatiotemporalDB", "ReActParser", "ReActTools"]


def __getattr__(name):
    if name == "MVA2Runner":
        from .runner import MVA2Runner
        return MVA2Runner
    if name == "JITVideoPipeline":
        from .pipeline import JITVideoPipeline
        return JITVideoPipeline
    if name == "SpatiotemporalDB":
        from .database import SpatiotemporalDB
        return SpatiotemporalDB
    if name in {"ReActParser", "ReActTools"}:
        from .agents import ReActParser, ReActTools
        return {"ReActParser": ReActParser, "ReActTools": ReActTools}[name]
    raise AttributeError(name)
