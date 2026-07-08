"""/fix command, auto-detection of messy links in chat, and the persistent
Fix / Copy / QR buttons.

Buttons are implemented with discord.ui.DynamicItem so they keep working
after the bot restarts: the button's custom_id only carries a small integer
row id, and the actual data (which URL it refers to) lives in SQLite.
"""
from __future__ import annotations

import io
import logging

import discord
import qrcode
from discord import app_commands
from discord.ext import commands

import db
import linkfix

log = logging.getLogger('bot.fix')


async def do_fix(bot, original_url: str) -> tuple[linkfix.CleanResult, str, str | None]:
    """Cleans a URL and resolves redirects/title. Returns (clean_result, final_cleaned_url, title)."""
    result = linkfix.clean_url(original_url)
    cleaned = result.cleaned
    title = None

    meta = await linkfix.resolve_url(bot.http_session, cleaned)
    final_url = meta.get('final_url')
    if final_url and final_url != cleaned:
        try:
            from urllib.parse import urlsplit
            if (urlsplit(final_url).hostname or '') != (urlsplit(cleaned).hostname or ''):
                reresolved = linkfix.clean_url(final_url)
                cleaned = reresolved.cleaned
                result.changes.append(linkfix.Change('redirect', f'Redirects to {urlsplit(cleaned).hostname}'))
        except Exception:
            pass
    title = meta.get('title')

    return result, cleaned, title


def build_result_embed(original_url: str, cleaned_url: str, result: linkfix.CleanResult, title: str | None) -> discord.Embed:
    embed = discord.Embed(title='Link fixed', color=discord.Color.green())
    if title:
        embed.description = title
    embed.add_field(name='Original', value=f'```{original_url[:1000]}```', inline=False)
    embed.add_field(name='Fixed', value=f'```{cleaned_url[:1000]}```', inline=False)
    embed.add_field(name='Platform', value=result.platform, inline=True)
    embed.add_field(name='Changes', value=', '.join(c.label for c in result.changes) or 'None', inline=True)
    return embed


async def build_result_view(bot, fix_id: int, cleaned_url: str) -> discord.ui.View:
    view = discord.ui.View(timeout=None)
    view.add_item(discord.ui.Button(label='Open', style=discord.ButtonStyle.link, url=cleaned_url))
    view.add_item(CopyButton(fix_id))
    view.add_item(QrButton(fix_id))
    return view


class CopyButton(discord.ui.DynamicItem[discord.ui.Button], template=r'copybtn:(?P<id>[0-9]+)'):
    def __init__(self, fix_id: int):
        super().__init__(
            discord.ui.Button(
                label='Copy',
                style=discord.ButtonStyle.secondary,
                custom_id=f'copybtn:{fix_id}',
                emoji='\N{CLIPBOARD}',
            )
        )
        self.fix_id = fix_id

    @classmethod
    async def from_custom_id(cls, interaction, item, match):
        return cls(int(match['id']))

    async def callback(self, interaction: discord.Interaction):
        row = await db.get_fix_result(interaction.client.db, self.fix_id)
        if not row:
            await interaction.response.send_message('That result has expired.', ephemeral=True)
            return
        await interaction.response.send_message(f"```\n{row['cleaned_url']}\n```", ephemeral=True)


class QrButton(discord.ui.DynamicItem[discord.ui.Button], template=r'qrbtn:(?P<id>[0-9]+)'):
    def __init__(self, fix_id: int):
        super().__init__(
            discord.ui.Button(
                label='QR Code',
                style=discord.ButtonStyle.secondary,
                custom_id=f'qrbtn:{fix_id}',
                emoji='\N{FRAME WITH PICTURE}',
            )
        )
        self.fix_id = fix_id

    @classmethod
    async def from_custom_id(cls, interaction, item, match):
        return cls(int(match['id']))

    async def callback(self, interaction: discord.Interaction):
        row = await db.get_fix_result(interaction.client.db, self.fix_id)
        if not row:
            await interaction.response.send_message('That result has expired.', ephemeral=True)
            return
        img = qrcode.make(row['cleaned_url'])
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        buf.seek(0)
        await interaction.response.send_message(
            file=discord.File(buf, filename='qr.png'),
            ephemeral=True,
        )


class FixButton(discord.ui.DynamicItem[discord.ui.Button], template=r'fixbtn:(?P<id>[0-9]+)'):
    def __init__(self, pending_id: int):
        super().__init__(
            discord.ui.Button(
                label='Fix Link',
                style=discord.ButtonStyle.primary,
                custom_id=f'fixbtn:{pending_id}',
                emoji='\N{WRENCH}',
            )
        )
        self.pending_id = pending_id

    @classmethod
    async def from_custom_id(cls, interaction, item, match):
        return cls(int(match['id']))

    async def callback(self, interaction: discord.Interaction):
        await interaction.response.defer(ephemeral=True, thinking=True)
        bot = interaction.client
        pending = await db.get_pending_link(bot.db, self.pending_id)
        if not pending:
            await interaction.followup.send('This link is no longer available.', ephemeral=True)
            return

        original_url = pending['original_url']
        result, cleaned, title = await do_fix(bot, original_url)

        fix_id = await db.add_fix_result(bot.db, original_url=original_url, cleaned_url=cleaned, platform=result.platform)
        await db.add_history(bot.db, user_id=interaction.user.id, original_url=original_url,
                              cleaned_url=cleaned, platform=result.platform)

        embed = build_result_embed(original_url, cleaned, result, title)
        view = await build_result_view(bot, fix_id, cleaned)
        await interaction.followup.send(embed=embed, view=view, ephemeral=True)


# Links that clean_url() would meaningfully change (tracker stripped or
# domain converted). Used to decide whether the auto-detect prompt is worth
# showing at all, so the bot doesn't comment on already-clean links.
def _worth_fixing(result: linkfix.CleanResult) -> bool:
    return any(c.type in ('trackers', 'embed', 'redirect') for c in result.changes)


class FixCog(commands.Cog):
    def __init__(self, bot: commands.Bot):
        self.bot = bot
        bot.add_dynamic_items(FixButton, CopyButton, QrButton)

    @app_commands.command(name='fix', description='Clean trackers and fix embeds for a link')
    @app_commands.describe(link='The URL to clean up')
    async def fix(self, interaction: discord.Interaction, link: str):
        await interaction.response.defer(thinking=True)
        try:
            result, cleaned, title = await do_fix(self.bot, link)
        except linkfix.InvalidUrlError as e:
            await interaction.followup.send(str(e), ephemeral=True)
            return

        fix_id = await db.add_fix_result(self.bot.db, original_url=link, cleaned_url=cleaned, platform=result.platform)
        await db.add_history(self.bot.db, user_id=interaction.user.id, original_url=link,
                              cleaned_url=cleaned, platform=result.platform)

        embed = build_result_embed(link, cleaned, result, title)
        view = await build_result_view(self.bot, fix_id, cleaned)
        await interaction.followup.send(embed=embed, view=view)

    @commands.Cog.listener()
    async def on_message(self, message: discord.Message):
        if not self.bot.auto_detect_enabled:
            return
        if message.author.bot or not message.guild:
            return

        url = linkfix.extract_first_url(message.content)
        if not url:
            return

        try:
            result = linkfix.clean_url(url)
        except linkfix.InvalidUrlError:
            return

        if not _worth_fixing(result):
            return

        pending_id = await db.add_pending_link(
            self.bot.db,
            guild_id=message.guild.id,
            channel_id=message.channel.id,
            message_id=message.id,
            author_id=message.author.id,
            original_url=url,
        )

        view = discord.ui.View(timeout=None)
        view.add_item(FixButton(pending_id))
        try:
            await message.reply(
                'This link has trackers or a better embed available.',
                view=view,
                mention_author=False,
            )
        except discord.HTTPException:
            pass


async def setup(bot: commands.Bot):
    await bot.add_cog(FixCog(bot))
