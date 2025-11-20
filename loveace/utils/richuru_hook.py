import logging
import os
import sys
import types
from datetime import datetime
from logging import LogRecord
from pathlib import Path
from typing import Callable, Iterable, List, Optional, Union

from loguru import logger
from rich.console import Console, ConsoleRenderable
from rich.text import Text
from rich.theme import Theme
from rich.traceback import Traceback
from richuru import ExceptionHook, LoguruHandler, LoguruRichHandler, _loguru_exc_hook


class HookedLoguruRichHandler(LoguruRichHandler):
    """
    A hooked version of LoguruRichHandler to fix some issues.
    """

    def render(
        self,
        *,
        record: LogRecord,
        traceback: Optional[Traceback],
        message_renderable: "ConsoleRenderable",
    ) -> "ConsoleRenderable":
        """Render log for display.

        Args:
            record (LogRecord): logging Record.
            traceback (Optional[Traceback]): Traceback instance or None for no Traceback.
            message_renderable (ConsoleRenderable): Renderable (typically Text) containing log message contents.

        Returns:
            ConsoleRenderable: Renderable to display log.
        """
        current_path = Path(os.getcwd())
        path = Path(record.pathname)
        try:
            path = path.relative_to(current_path)
            if sys.platform == "win32":
                path = str(path).replace("\\", "/")
        except ValueError:
            path = Path(record.pathname).name
        path = str(path)
        level = self.get_level_text(record)
        time_format = None if self.formatter is None else self.formatter.datefmt
        log_time = datetime.fromtimestamp(record.created)

        log_renderable = self._log_render(
            self.console,
            [message_renderable] if not traceback else [message_renderable, traceback],
            log_time=log_time,
            time_format=time_format,
            level=level,
            path=path,
            line_no=record.lineno,
            link_path=record.pathname if self.enable_link_path else None,
        )
        return log_renderable


def install(
    rich_console: Optional[Console] = None,
    exc_hook: Optional[ExceptionHook] = _loguru_exc_hook,
    rich_traceback: bool = True,
    tb_ctx_lines: int = 3,
    tb_theme: Optional[str] = None,
    tb_suppress: Iterable[Union[str, types.ModuleType]] = (),
    time_format: Union[str, Callable[[datetime], Text]] = "[%x %X]",
    keywords: Optional[List[str]] = None,
    level: Union[int, str] = 20,
) -> None:
    """Install Rich logging and Loguru exception hook"""
    logging.basicConfig(handlers=[LoguruHandler()], level=0)
    logger.configure(
        handlers=[
            {
                "sink": HookedLoguruRichHandler(
                    console=rich_console
                    or Console(
                        theme=Theme(
                            {
                                "logging.level.success": "green",
                                "logging.level.trace": "bright_black",
                            }
                        )
                    ),
                    rich_tracebacks=rich_traceback,
                    tracebacks_show_locals=True,
                    tracebacks_suppress=tb_suppress,
                    tracebacks_extra_lines=tb_ctx_lines,
                    tracebacks_theme=tb_theme,
                    show_time=False,
                    log_time_format=time_format,
                    keywords=keywords,
                ),
                "format": (lambda _: "{message}") if rich_traceback else "{message}",
                "level": level,
            }
        ]
    )
    if exc_hook is not None:
        sys.excepthook = exc_hook
