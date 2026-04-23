import { useState, useCallback, useEffect } from 'react';
import {
    getPlayers,
    getPlayerDetail,
    getPlayerPortraitDocument,
    getPlayerBadgeDocument,
    getPlayerIdDocument,
    requestPlayerInfoVerification,
    sendPlayerVideoRequest,
    submitExpertReview,
    submitScouterDecision,
    updatePreContract,
} from '../api/players';
import { deleteUser, banUser, unbanUser } from '../api/users';
import { useApi } from '../hooks/useApi';
import { DataTable, type Column } from '../components/ui/DataTable';
import { PillBadge } from '../components/ui/PillBadge';
import { Button } from '../components/ui/Button';
import { SearchInput } from '../components/ui/SearchInput';
import { Pagination } from '../components/ui/Pagination';
import { ConfirmDialog } from '../components/ui/ConfirmDialog';
import { MetricTile } from '../components/ui/MetricTile';
import { GlassCard } from '../components/ui/GlassCard';
import { useAuth } from '../context/AuthContext';
import type { AdminPlayer, PlayerDetail, PlayerWorkflow } from '../types';
import type { PlayerDocumentFile } from '../api/players';
import { PDFDocument, StandardFonts } from 'pdf-lib';

function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
}

function calcAge(dob: string | null | undefined): string {
    if (!dob) return '—';
    const birth = new Date(dob);
    const today = new Date();
    const age = today.getFullYear() - birth.getFullYear();
    return String(age);
}

type VerificationStatus = 'not_requested' | 'pending_expert' | 'verified' | 'rejected';
type PreContractStatus = 'none' | 'draft' | 'approved' | 'cancelled';

interface PlayerWorkflowState extends PlayerWorkflow {}

function createDefaultWorkflowState(): PlayerWorkflowState {
    return {
        sentVideoRequests: 0,
        verificationStatus: 'not_requested',
        scouterDecision: 'pending',
        expertDecision: 'pending',
        expertReport: '',
        fixedPrice: 0,
        preContractStatus: 'none',
        updatedAt: new Date().toISOString(),
    };
}

// ── Detail Panel ────────────────────────────────────────────────────────────

function PlayerDetailPanel({
    playerId,
    onClose,
    onAction,
    viewerRole,
    workflow,
    onUpdateWorkflow,
}: {
    playerId: string;
    onClose: () => void;
    onAction: () => void;
    viewerRole: 'admin' | 'expert';
    workflow: PlayerWorkflowState;
    onUpdateWorkflow: (updater: (previous: PlayerWorkflowState) => PlayerWorkflowState) => void;
}) {
    const fetcher = useCallback(() => getPlayerDetail(playerId), [playerId]);
    const { data, loading, error, refetch } = useApi(fetcher, [playerId]);
    const [portraitDoc, setPortraitDoc] = useState<PlayerDocumentFile | null>(null);
    const [badgeDoc, setBadgeDoc] = useState<PlayerDocumentFile | null>(null);
    const [playerIdDoc, setPlayerIdDoc] = useState<PlayerDocumentFile | null>(null);
    const [portraitUrl, setPortraitUrl] = useState<string | null>(null);
    const [badgeUrl, setBadgeUrl] = useState<string | null>(null);
    const [playerIdUrl, setPlayerIdUrl] = useState<string | null>(null);
    const [documentsLoading, setDocumentsLoading] = useState(false);

    const refreshDocuments = useCallback(async () => {
        setDocumentsLoading(true);
        try {
            const [portraitBlob, badgeBlob, playerIdBlob] = await Promise.all([
                getPlayerPortraitDocument(playerId),
                getPlayerBadgeDocument(playerId),
                getPlayerIdDocument(playerId),
            ]);

            setPortraitDoc(portraitBlob);
            setBadgeDoc(badgeBlob);
            setPlayerIdDoc(playerIdBlob);

            setPortraitUrl((previous) => {
                if (previous) URL.revokeObjectURL(previous);
                return portraitBlob ? URL.createObjectURL(portraitBlob.blob) : null;
            });
            setBadgeUrl((previous) => {
                if (previous) URL.revokeObjectURL(previous);
                return badgeBlob ? URL.createObjectURL(badgeBlob.blob) : null;
            });
            setPlayerIdUrl((previous) => {
                if (previous) URL.revokeObjectURL(previous);
                return playerIdBlob ? URL.createObjectURL(playerIdBlob.blob) : null;
            });
        } catch {
            setPortraitDoc(null);
            setBadgeDoc(null);
            setPlayerIdDoc(null);
            setPortraitUrl((previous) => {
                if (previous) URL.revokeObjectURL(previous);
                return null;
            });
            setBadgeUrl((previous) => {
                if (previous) URL.revokeObjectURL(previous);
                return null;
            });
            setPlayerIdUrl((previous) => {
                if (previous) URL.revokeObjectURL(previous);
                return null;
            });
        } finally {
            setDocumentsLoading(false);
        }
    }, [playerId]);

    useEffect(() => {
        if (data?.workflow) {
            onUpdateWorkflow(() => data.workflow as PlayerWorkflowState);
        }
    }, [data?.workflow]);

    useEffect(() => {
        void refreshDocuments();

        return () => {
            setPortraitDoc(null);
            setBadgeDoc(null);
            setPlayerIdDoc(null);
            setPortraitUrl((previous) => {
                if (previous) URL.revokeObjectURL(previous);
                return null;
            });
            setBadgeUrl((previous) => {
                if (previous) URL.revokeObjectURL(previous);
                return null;
            });
            setPlayerIdUrl((previous) => {
                if (previous) URL.revokeObjectURL(previous);
                return null;
            });
        };
    }, [refreshDocuments]);

    function updateWorkflow(updater: (previous: PlayerWorkflowState) => PlayerWorkflowState) {
        onUpdateWorkflow((previous) => ({ ...updater(previous), updatedAt: new Date().toISOString() }));
    }

    async function handleSendVideoRequest() {
        try {
            const next = await sendPlayerVideoRequest(playerId);
            onUpdateWorkflow(() => next);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Unable to send video request');
        }
    }

    async function handleRequestInfoVerification() {
        try {
            const next = await requestPlayerInfoVerification(playerId);
            onUpdateWorkflow(() => next);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Unable to request verification');
        }
    }

    async function handleExpertDecision(nextDecision: 'approved' | 'cancelled') {
        try {
            const next = await submitExpertReview(playerId, {
                decision: nextDecision,
                report: workflow.expertReport,
            });
            onUpdateWorkflow(() => next);
            refetch();
            onAction();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Unable to save expert decision');
        }
    }

    async function handleSendExpertReport() {
        try {
            const next = await submitExpertReview(playerId, {
                decision: workflow.expertDecision === 'cancelled' ? 'cancelled' : 'approved',
                report: workflow.expertReport,
            });
            onUpdateWorkflow(() => next);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Unable to send expert report');
        }
    }

    async function handleExportExpertPdf() {
        if (!data) return;

        try {
            const pdfDoc = await PDFDocument.create();
            const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
            const bold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

            const pageWidth = 595;
            const pageHeight = 842;
            const margin = 40;
            const lineHeight = 17;

            const first = pdfDoc.addPage([pageWidth, pageHeight]);
            let y = pageHeight - margin;

            const drawLine = (page: any, label: string, value: string, isTitle = false) => {
                const text = isTitle ? label : `${label}: ${value}`;
                const size = isTitle ? 18 : 11;
                const usedFont = isTitle ? bold : font;
                page.drawText(text, {
                    x: margin,
                    y,
                    size,
                    font: usedFont,
                });
                y -= isTitle ? 24 : lineHeight;
            };

            drawLine(first, 'Expert Player Private Export', '', true);
            drawLine(first, 'Generated at', new Date().toLocaleString());
            y -= 8;
            drawLine(first, 'Player Private Data', '', true);
            drawLine(first, 'Name', data.player.displayName || '—');
            drawLine(first, 'Email', data.player.email || '—');
            drawLine(first, 'Position', data.player.position || '—');
            drawLine(first, 'Nation', data.player.nation || '—');
            drawLine(first, 'Age', calcAge(data.player.dateOfBirth));
            drawLine(first, 'Height', data.player.height ? `${data.player.height} cm` : '—');
            drawLine(first, 'Government ID', String((data.player as any).playerIdNumber || '—'));
            drawLine(first, 'Joined', formatDate(data.player.createdAt));
            drawLine(first, 'Plan', data.player.subscriptionTier || 'None');
            y -= 8;
            drawLine(first, 'Workflow', '', true);
            drawLine(first, 'Verification Status', workflow.verificationStatus);
            drawLine(first, 'Expert Decision', workflow.expertDecision);
            drawLine(first, 'Scouter Decision', workflow.scouterDecision);
            drawLine(first, 'Pre-Contract', workflow.preContractStatus);
            drawLine(first, 'Fixed Price', String(workflow.fixedPrice));
            drawLine(first, 'Platform Fee (3%)', (workflow.fixedPrice * 0.03).toFixed(2));
            drawLine(first, 'Expert Verification Fee', 'USD 30 (paid by platform)');
            drawLine(first, 'Updated At', formatDate(workflow.updatedAt));
            drawLine(first, 'Expert Note', workflow.expertReport || 'No note');

            const appendUnsupportedPage = (label: string, fileName: string, contentType: string) => {
                const p = pdfDoc.addPage([pageWidth, pageHeight]);
                let py = pageHeight - margin;
                p.drawText(`${label} - ${fileName}`, { x: margin, y: py, size: 14, font: bold });
                py -= 26;
                p.drawText('Document attached in system but this format cannot be embedded in PDF export.', {
                    x: margin,
                    y: py,
                    size: 11,
                    font,
                });
                py -= 16;
                p.drawText(`Content-Type: ${contentType || 'unknown'}`, {
                    x: margin,
                    y: py,
                    size: 11,
                    font,
                });
            };

            const appendImagePage = async (label: string, doc: PlayerDocumentFile) => {
                const bytes = new Uint8Array(await doc.blob.arrayBuffer());
                const type = (doc.contentType || '').toLowerCase();
                const p = pdfDoc.addPage([pageWidth, pageHeight]);
                let embedded: any = null;
                if (type.includes('png')) {
                    embedded = await pdfDoc.embedPng(bytes);
                } else if (type.includes('jpeg') || type.includes('jpg')) {
                    embedded = await pdfDoc.embedJpg(bytes);
                } else {
                    appendUnsupportedPage(label, doc.fileName || 'uploaded', doc.contentType || '');
                    return;
                }

                const top = pageHeight - margin;
                p.drawText(`${label} - ${doc.fileName || 'uploaded'}`, {
                    x: margin,
                    y: top,
                    size: 14,
                    font: bold,
                });

                const maxWidth = pageWidth - margin * 2;
                const maxHeight = pageHeight - margin * 2 - 28;
                const ratio = Math.min(maxWidth / embedded.width, maxHeight / embedded.height, 1);
                const drawWidth = embedded.width * ratio;
                const drawHeight = embedded.height * ratio;

                p.drawImage(embedded, {
                    x: margin + (maxWidth - drawWidth) / 2,
                    y: margin + (maxHeight - drawHeight) / 2,
                    width: drawWidth,
                    height: drawHeight,
                });
            };

            const appendPdfPages = async (label: string, doc: PlayerDocumentFile) => {
                const srcBytes = await doc.blob.arrayBuffer();
                const srcDoc = await PDFDocument.load(srcBytes);
                const cover = pdfDoc.addPage([pageWidth, pageHeight]);
                cover.drawText(`${label} - ${doc.fileName || 'uploaded'}`, {
                    x: margin,
                    y: pageHeight - margin,
                    size: 14,
                    font: bold,
                });
                cover.drawText('Pages from uploaded PDF are appended below.', {
                    x: margin,
                    y: pageHeight - margin - 22,
                    size: 11,
                    font,
                });

                const copied = await pdfDoc.copyPages(srcDoc, srcDoc.getPageIndices());
                copied.forEach((page) => pdfDoc.addPage(page));
            };

            const appendDocument = async (label: string, doc: PlayerDocumentFile | null) => {
                if (!doc) {
                    const p = pdfDoc.addPage([pageWidth, pageHeight]);
                    p.drawText(`${label} - Not uploaded`, {
                        x: margin,
                        y: pageHeight - margin,
                        size: 14,
                        font: bold,
                    });
                    return;
                }

                const type = (doc.contentType || '').toLowerCase();
                if (type.includes('application/pdf')) {
                    await appendPdfPages(label, doc);
                    return;
                }
                if (type.startsWith('image/')) {
                    await appendImagePage(label, doc);
                    return;
                }
                appendUnsupportedPage(label, doc.fileName || 'uploaded', doc.contentType || '');
            };

            await appendDocument('Medical Diploma', badgeDoc);
            await appendDocument('Bulletin n3', portraitDoc);
            await appendDocument('Player Government ID Document', playerIdDoc);

            const bytes = await pdfDoc.save();
            const blob = new Blob([Uint8Array.from(bytes)], { type: 'application/pdf' });
            const fileUrl = URL.createObjectURL(blob);
            const playerName = (data.player.displayName || 'player').replace(/[^a-z0-9-_]/gi, '_');
            triggerDownload(fileUrl, `expert-private-export-${playerName}.pdf`);
            window.setTimeout(() => URL.revokeObjectURL(fileUrl), 2000);
        } catch {
            alert('Unable to generate merged PDF export. Please refresh documents and try again.');
        }
    }

    async function handleScouterDecision(nextDecision: 'approved' | 'cancelled') {
        try {
            const next = await submitScouterDecision(playerId, { decision: nextDecision });
            onUpdateWorkflow(() => next);
            refetch();
            onAction();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Unable to save scouter decision');
        }
    }

    async function handlePreContractStatus(nextStatus: PreContractStatus) {
        try {
            const next = await updatePreContract(playerId, {
                status: nextStatus,
                fixedPrice: workflow.fixedPrice,
            });
            onUpdateWorkflow(() => next.workflow);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Unable to update pre-contract');
        }
    }

    function triggerDownload(fileUrl: string, fileName: string) {
        const link = document.createElement('a');
        link.href = fileUrl;
        link.download = fileName || 'document';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    function handleOpenFile(fileUrl: string) {
        const popup = window.open(fileUrl, '_blank', 'noopener,noreferrer');
        if (!popup) {
            // Popup blocked: fallback to download so user still gets the file.
            triggerDownload(fileUrl, 'document');
        }
    }

    return (
        <div style={panelOverlay} onClick={onClose}>
            <div style={panelDrawer} onClick={(e) => e.stopPropagation()}>
                {/* Header */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
                    <div>
                        <h2 style={{ fontSize: 20, fontWeight: 900, color: 'var(--color-text)', margin: 0 }}>
                            {loading ? 'Loading…' : data?.player.displayName || data?.player.email || '—'}
                        </h2>
                        <div style={{ fontSize: 12, color: 'var(--color-text-muted)', marginTop: 2 }}>
                            Player Profile
                        </div>
                    </div>
                    <button
                        onClick={onClose}
                        style={{ background: 'none', border: 'none', color: 'var(--color-text-muted)', fontSize: 20, cursor: 'pointer' }}
                    >
                        ✕
                    </button>
                </div>

                {loading && <div style={{ color: 'var(--color-text-muted)', padding: 40, textAlign: 'center' }}>Loading…</div>}
                {error && <div style={{ color: 'var(--color-danger)', padding: 20 }}>{error}</div>}

                {data && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
                        {viewerRole === 'admin' && (
                            <GlassCard>
                                <div style={sectionTitle}>Scouter Actions</div>
                                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                                    <Button size="sm" variant="primary" onClick={() => void handleSendVideoRequest()}>
                                        Send Video Request
                                    </Button>
                                    <Button size="sm" variant="warning" onClick={() => void handleRequestInfoVerification()}>
                                        Request Info Verification
                                    </Button>
                                </div>
                                <div style={workflowHintStyle}>
                                    Sent requests: <strong>{workflow.sentVideoRequests}</strong>
                                </div>
                            </GlassCard>
                        )}

                        <GlassCard>
                            <div style={sectionTitle}>Verification Status</div>
                            <div style={workflowBadgeRowStyle}>
                                <StatusBadge label={workflow.verificationStatus} />
                                <StatusBadge label={`expert:${workflow.expertDecision}`} subtle />
                                <StatusBadge label={`scouter:${workflow.scouterDecision}`} subtle />
                            </div>
                            <div style={workflowHintStyle}>
                                Last update: {formatDate(workflow.updatedAt)}
                            </div>
                        </GlassCard>

                        {/* Analytics tiles */}
                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(130px, 1fr))', gap: 10 }}>
                            <StatBox label="Videos" value={String(data.analytics.totalVideos)} icon="🎬" />
                            <StatBox label="Analyzed" value={String(data.analytics.analyzedVideos)} icon="📊" />
                            <StatBox label="Reports" value={String(data.analytics.reportsAboutPlayer)} icon="📋" />
                            <StatBox label="Max Speed" value={`${data.analytics.maxSpeedKmh} km/h`} icon="⚡" />
                            <StatBox label="Avg Speed" value={`${data.analytics.avgSpeedKmh} km/h`} icon="🏃" />
                            <StatBox label="Sprints" value={String(data.analytics.totalSprints)} icon="💨" />
                        </div>

                        {/* Profile info */}
                        <GlassCard>
                            <div style={sectionTitle}>Profile</div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '6px 20px' }}>
                                <InfoRow label="Email" value={data.player.email} />
                                <InfoRow label="Position" value={data.player.position || '—'} />
                                <InfoRow label="Nation" value={data.player.nation || '—'} />
                                <InfoRow label="Age" value={calcAge(data.player.dateOfBirth)} />
                                <InfoRow label="Height" value={data.player.height ? `${data.player.height} cm` : '—'} />
                                <InfoRow label="Badge" value={data.player.badgeVerified ? '✅ Verified' : '—'} />
                                <InfoRow label="Plan" value={data.player.subscriptionTier || 'None'} />
                                <InfoRow label="Joined" value={formatDate(data.player.createdAt)} />
                            </div>
                        </GlassCard>

                        {/* Videos */}
                        {data.videos.length > 0 && (
                            <GlassCard>
                                <div style={sectionTitle}>Videos ({data.videos.length})</div>
                                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 180, overflowY: 'auto' }}>
                                    {data.videos.map((v) => (
                                        <div key={v._id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, padding: '4px 0', borderBottom: '1px solid var(--color-border)' }}>
                                            <span style={{ color: 'var(--color-text)', fontWeight: 600 }}>{v.originalName}</span>
                                            <span style={{ color: 'var(--color-text-muted)' }}>{formatDate(v.createdAt)}</span>
                                        </div>
                                    ))}
                                </div>
                            </GlassCard>
                        )}

                        {/* Reports */}
                        {data.reports.length > 0 && (
                            <GlassCard>
                                <div style={sectionTitle}>Scouting Reports ({data.reports.length})</div>
                                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 180, overflowY: 'auto' }}>
                                    {data.reports.map((r) => (
                                        <div key={r._id} style={{ fontSize: 12, padding: '6px 0', borderBottom: '1px solid var(--color-border)' }}>
                                            <div style={{ fontWeight: 700, color: 'var(--color-text)' }}>{r.title || '(untitled)'}</div>
                                            <div style={{ color: 'var(--color-text-muted)', marginTop: 2 }}>
                                                {r.notes.length > 80 ? r.notes.slice(0, 80) + '…' : r.notes}
                                            </div>
                                            <div style={{ color: 'var(--color-text-muted)', marginTop: 2 }}>{formatDate(r.createdAt)}</div>
                                        </div>
                                    ))}
                                </div>
                            </GlassCard>
                        )}

                        <GlassCard>
                            <div style={sectionTitle}>Expert Workflow</div>
                            <div style={resourceBoxStyle}>
                                <div style={resourceTitleStyle}>Player Documents</div>
                                <div style={resourceItemStyle}>Medical diploma and Bulletin n3 review.</div>
                                <div style={resourceItemStyle}>Physical verification is done in real life by expert.</div>
                            </div>

                            <div style={{ marginTop: 12 }}>
                                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
                                    <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--color-text)' }}>
                                        Documents
                                    </div>
                                    <Button size="sm" variant="ghost" onClick={() => void refreshDocuments()}>
                                        Refresh documents
                                    </Button>
                                </div>
                                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
                                    <div style={docCardStyle}>
                                        <div style={docTitleStyle}>Medical Diploma</div>
                                        {documentsLoading ? (
                                            <div style={docHintStyle}>Loading...</div>
                                        ) : badgeUrl && badgeDoc?.contentType.startsWith('image/') ? (
                                            <a href={badgeUrl} target="_blank" rel="noreferrer" style={{ display: 'block' }}>
                                                <img src={badgeUrl} alt="Medical diploma" style={docImageStyle} />
                                            </a>
                                        ) : badgeUrl ? (
                                            <>
                                                <div style={docHintStyle}>File uploaded: {badgeDoc?.fileName || 'medical-diploma'}</div>
                                                <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                                                    <Button size="sm" variant="ghost" onClick={() => handleOpenFile(badgeUrl)}>
                                                        Open file
                                                    </Button>
                                                    <Button size="sm" variant="ghost" onClick={() => triggerDownload(badgeUrl, badgeDoc?.fileName || 'medical-diploma')}>
                                                        Download
                                                    </Button>
                                                </div>
                                            </>
                                        ) : (
                                            <div style={docHintStyle}>Not uploaded</div>
                                        )}
                                    </div>
                                    <div style={docCardStyle}>
                                        <div style={docTitleStyle}>Bulletin n3</div>
                                        {documentsLoading ? (
                                            <div style={docHintStyle}>Loading...</div>
                                        ) : portraitUrl && portraitDoc?.contentType.startsWith('image/') ? (
                                            <a href={portraitUrl} target="_blank" rel="noreferrer" style={{ display: 'block' }}>
                                                <img src={portraitUrl} alt="Bulletin n3" style={docImageStyle} />
                                            </a>
                                        ) : portraitUrl ? (
                                            <>
                                                <div style={docHintStyle}>File uploaded: {portraitDoc?.fileName || 'bulletin-n3'}</div>
                                                <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                                                    <Button size="sm" variant="ghost" onClick={() => handleOpenFile(portraitUrl)}>
                                                        Open file
                                                    </Button>
                                                    <Button size="sm" variant="ghost" onClick={() => triggerDownload(portraitUrl, portraitDoc?.fileName || 'bulletin-n3')}>
                                                        Download
                                                    </Button>
                                                </div>
                                            </>
                                        ) : (
                                            <div style={docHintStyle}>Not uploaded</div>
                                        )}
                                    </div>
                                    <div style={docCardStyle}>
                                        <div style={docTitleStyle}>Player ID Document</div>
                                        {documentsLoading ? (
                                            <div style={docHintStyle}>Loading...</div>
                                        ) : playerIdUrl && playerIdDoc?.contentType.startsWith('image/') ? (
                                            <a href={playerIdUrl} target="_blank" rel="noreferrer" style={{ display: 'block' }}>
                                                <img src={playerIdUrl} alt="Player ID document" style={docImageStyle} />
                                            </a>
                                        ) : playerIdUrl ? (
                                            <>
                                                <div style={docHintStyle}>File uploaded: {playerIdDoc?.fileName || 'player-id'}</div>
                                                <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                                                    <Button size="sm" variant="ghost" onClick={() => handleOpenFile(playerIdUrl)}>
                                                        Open file
                                                    </Button>
                                                    <Button size="sm" variant="ghost" onClick={() => triggerDownload(playerIdUrl, playerIdDoc?.fileName || 'player-id')}>
                                                        Download
                                                    </Button>
                                                </div>
                                            </>
                                        ) : (
                                            <div style={docHintStyle}>Not uploaded</div>
                                        )}
                                    </div>
                                </div>
                                <div style={{ marginTop: 8, fontSize: 12, color: 'var(--color-text-muted)' }}>
                                    Player Government ID number: <strong style={{ color: 'var(--color-text)' }}>{String((data.player as any).playerIdNumber || 'Not provided')}</strong>
                                </div>
                            </div>

                            {viewerRole === 'expert' ? (
                                <>
                                    <div style={{ marginTop: 10 }}>
                                        <textarea
                                            value={workflow.expertReport}
                                            onChange={(e) => updateWorkflow((previous) => ({ ...previous, expertReport: e.target.value }))}
                                            placeholder="Optional expert note for real-life verification"
                                            style={reportInputStyle}
                                        />
                                    </div>
                                    <div style={{ marginTop: 10 }}>
                                        <div style={workflowHintStyle}>Expert earns USD 30 per verified player. Withdraw from Profile.</div>
                                    </div>
                                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
                                        <Button size="sm" variant="ghost" onClick={handleExportExpertPdf}>
                                            Export PDF
                                        </Button>
                                        <Button size="sm" variant="primary" onClick={() => void handleExpertDecision('approved')}>
                                            Verified
                                        </Button>
                                    </div>
                                </>
                            ) : (
                                <div style={workflowHintStyle}>Expert can review documents and validate in real life.</div>
                            )}
                        </GlassCard>

                        {viewerRole === 'admin' && (
                            <GlassCard>
                                <div style={sectionTitle}>Scouter Approval</div>
                                <div style={workflowHintStyle}>
                                    Approve player after expert verification or cancel the process.
                                </div>
                                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
                                    <Button
                                        size="sm"
                                        variant="primary"
                                        onClick={() => void handleScouterDecision('approved')}
                                        disabled={workflow.verificationStatus !== 'verified'}
                                    >
                                        Approve Player
                                    </Button>
                                    <Button size="sm" variant="danger" onClick={() => void handleScouterDecision('cancelled')}>
                                        Cancel
                                    </Button>
                                </div>
                            </GlassCard>
                        )}

                        {viewerRole === 'admin' && (
                            <GlassCard>
                                <div style={sectionTitle}>Pre-Contract Workflow</div>
                                <div style={workflowHintStyle}>Contract economics: platform takes 3% of fixed contract price; expert receives a fixed USD 30 verification fee paid by platform.</div>
                                <div style={{ display: 'grid', gridTemplateColumns: '1fr auto', gap: 10, alignItems: 'end', marginTop: 10 }}>
                                    <div>
                                        <label style={inputLabelStyle}>Fixed Price</label>
                                        <input
                                            type="number"
                                            min={0}
                                            step="100"
                                            value={workflow.fixedPrice}
                                            onChange={async (e) => {
                                                const nextFixedPrice = Number(e.target.value) || 0;
                                                updateWorkflow((previous) => ({ ...previous, fixedPrice: nextFixedPrice }));
                                                try {
                                                    const next = await updatePreContract(playerId, { fixedPrice: nextFixedPrice });
                                                    onUpdateWorkflow(() => next.workflow);
                                                } catch {
                                                    // Keep local value visible and retry on next pre-contract action.
                                                }
                                            }}
                                            style={contractInputStyle}
                                        />
                                    </div>
                                    <Button
                                        size="sm"
                                        variant="warning"
                                        disabled={workflow.fixedPrice <= 0 || workflow.scouterDecision !== 'approved'}
                                        onClick={() => void handlePreContractStatus('draft')}
                                    >
                                        Prepare Pre-Contract
                                    </Button>
                                </div>
                                <div style={workflowHintStyle}>
                                    Platform fee (3% of fixed price): {(workflow.fixedPrice * 0.03).toFixed(2)}
                                </div>
                                <div style={workflowHintStyle}>Expert verification fee: USD 30 (not deducted from player/scouter contract amount).</div>
                                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
                                    <Button
                                        size="sm"
                                        variant="primary"
                                        disabled={workflow.preContractStatus !== 'draft'}
                                        onClick={() => void handlePreContractStatus('approved')}
                                    >
                                        Confirm Pre-Contract
                                    </Button>
                                    <Button size="sm" variant="danger" onClick={() => void handlePreContractStatus('cancelled')}>
                                        Cancel Pre-Contract
                                    </Button>
                                </div>
                                <div style={workflowHintStyle}>Current status: {workflow.preContractStatus}</div>
                            </GlassCard>
                        )}
                    </div>
                )}
            </div>
        </div>
    );
}

// ── Main Page ────────────────────────────────────────────────────────────────

export function PlayersPage() {
    const { role } = useAuth();
    const [page, setPage] = useState(1);
    const [search, setSearch] = useState('');
    const [tierFilter, setTierFilter] = useState('');
    const [selectedId, setSelectedId] = useState<string | null>(null);
    const [deleteTarget, setDeleteTarget] = useState<AdminPlayer | null>(null);
    const [actionLoading, setActionLoading] = useState(false);
    const [playerWorkflows, setPlayerWorkflows] = useState<Record<string, PlayerWorkflowState>>({});

    const fetcher = useCallback(
        () => getPlayers({ page, limit: 20, search, subscriptionTier: tierFilter || undefined }),
        [page, search, tierFilter],
    );
    const { data, loading, refetch } = useApi(fetcher, [page, search, tierFilter]);

    const players = (data?.data ?? []) as AdminPlayer[];
    const total = data?.total ?? 0;

    // Summary KPIs from loaded slice
    const totalLoaded = players.length;
    const withBadge = players.filter((p) => p.badgeVerified).length;
    const banned = players.filter((p) => p.isBanned).length;
    const pendingExpert = players.filter((p) => p.adminWorkflow?.verificationStatus === 'pending_expert').length;
    const avgVideos = totalLoaded ? (players.reduce((s, p) => s + (p.videoCount ?? 0), 0) / totalLoaded).toFixed(1) : '0';

    async function handleDelete(player: AdminPlayer) {
        setActionLoading(true);
        try {
            await deleteUser(player._id);
            setDeleteTarget(null);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Delete failed');
        } finally {
            setActionLoading(false);
        }
    }

    async function handleToggleBan(player: AdminPlayer) {
        try {
            if (player.isBanned) await unbanUser(player._id);
            else await banUser(player._id);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Action failed');
        }
    }

    const columns: Column<Record<string, unknown>>[] = [
        {
            key: 'displayName',
            header: 'Player',
            render: (row) => {
                const needsExpert = (row as any).adminWorkflow?.verificationStatus === 'pending_expert';
                return (
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <div style={avatarStyle}>{(row.displayName as string || row.email as string || '?')[0].toUpperCase()}</div>
                    <div>
                        <div style={{ fontWeight: 700, fontSize: 13 }}>{(row.displayName as string) || '—'}</div>
                        <div style={{ fontSize: 11, color: 'var(--color-text-muted)' }}>{row.email as string}</div>
                        {role === 'expert' && needsExpert && (
                            <div style={{ fontSize: 10, color: 'var(--color-accent)', fontWeight: 700, marginTop: 2 }}>
                                Needs expert verification
                            </div>
                        )}
                    </div>
                </div>
            );
            },
        },
        {
            key: 'position',
            header: 'Position',
            render: (row) => <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>{(row.position as string) || '—'}</span>,
        },
        {
            key: 'nation',
            header: 'Nation',
            render: (row) => <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>{(row.nation as string) || '—'}</span>,
        },
        {
            key: 'age',
            header: 'Age',
            render: (row) => <span style={{ fontSize: 12 }}>{calcAge(row.dateOfBirth as string)}</span>,
        },
        {
            key: 'height',
            header: 'Height',
            render: (row) => <span style={{ fontSize: 12 }}>{row.height ? `${row.height} cm` : '—'}</span>,
        },
        {
            key: 'subscriptionTier',
            header: 'Plan',
            render: (row) =>
                row.subscriptionTier ? (
                    <PillBadge variant="warning">{row.subscriptionTier as string}</PillBadge>
                ) : (
                    <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>—</span>
                ),
        },
        {
            key: 'videoCount',
            header: 'Videos',
            render: (row) => (
                <span style={{ fontWeight: 700, color: 'var(--color-primary)', fontSize: 13 }}>{row.videoCount as number ?? 0}</span>
            ),
        },
        {
            key: 'reportCount',
            header: 'Reports',
            render: (row) => (
                <span style={{ fontWeight: 700, color: 'var(--color-accent)', fontSize: 13 }}>{row.reportCount as number ?? 0}</span>
            ),
        },
        {
            key: 'status',
            header: 'Status',
            render: (row) =>
                role === 'admin' && row.isBanned ? (
                    <PillBadge variant="danger">Banned</PillBadge>
                ) : (
                    <PillBadge variant="success">Active</PillBadge>
                ),
        },
        {
            key: 'verification',
            header: 'Verification',
            render: (row) => {
                const status = ((row as any).adminWorkflow?.verificationStatus || '').toString();
                if (status === 'pending_expert') {
                    return <PillBadge variant="primary">Needs Expert</PillBadge>;
                }
                if (status === 'rejected') {
                    return <PillBadge variant="danger">Rejected</PillBadge>;
                }
                return row.badgeVerified ? (
                    <PillBadge variant="success">Verified</PillBadge>
                ) : (
                    <PillBadge variant="warning">Pending</PillBadge>
                );
            },
        },
        {
            key: '_actions',
            header: '',
            width: 200,
            render: (row) => {
                const player = row as unknown as AdminPlayer;
                return (
                    <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                        <Button size="sm" variant="ghost" onClick={() => setSelectedId(player._id)} style={{ fontSize: 11 }}>
                            View
                        </Button>
                        {role === 'admin' && (
                            <>
                                <Button size="sm" variant="warning" onClick={() => handleToggleBan(player)} style={{ fontSize: 11 }}>
                                    {player.isBanned ? 'Unban' : 'Ban'}
                                </Button>
                                <Button size="sm" variant="danger" onClick={() => setDeleteTarget(player)} style={{ fontSize: 11 }}>
                                    Delete
                                </Button>
                            </>
                        )}
                    </div>
                );
            },
        },
    ];

    const handleUpdateSelectedWorkflow = useCallback(
        (updater: (previous: PlayerWorkflowState) => PlayerWorkflowState) => {
            if (!selectedId) return;
            setPlayerWorkflows((previous) => {
                const current = previous[selectedId] ?? createDefaultWorkflowState();
                return {
                    ...previous,
                    [selectedId]: updater(current),
                };
            });
        },
        [selectedId],
    );

    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            {/* KPI Tiles */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 14 }}>
                <MetricTile label="Total Players" value={total} valueColor="var(--color-primary)" icon="⚽" />
                <MetricTile label="Avg Videos / Player" value={Number(avgVideos)} valueColor="var(--color-text)" icon="🎬" />
                <MetricTile label="Badge Verified" value={withBadge} valueColor="var(--color-accent)" icon="✅" />
                {role === 'expert' && (
                    <MetricTile label="Need Verify" value={pendingExpert} valueColor="var(--color-warning)" icon="🧾" />
                )}
                {role === 'admin' && (
                    <MetricTile label="Banned" value={banned} valueColor="var(--color-danger)" icon="🚫" />
                )}
            </div>

            {/* Filters */}
            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center' }}>
                <SearchInput
                    value={search}
                    onChange={(v) => { setSearch(v); setPage(1); }}
                    placeholder="Search by name or email…"
                />
                <select
                    value={tierFilter}
                    onChange={(e) => { setTierFilter(e.target.value); setPage(1); }}
                    style={selectStyle}
                >
                    <option value="">All plans</option>
                    <option value="basic">Basic</option>
                    <option value="premium">Premium</option>
                    <option value="elite">Elite</option>
                </select>
            </div>

            {/* Table */}
            <DataTable
                columns={columns}
                rows={players as unknown as Record<string, unknown>[]}
                loading={loading}
                keyExtractor={(row) => String(row._id)}
                emptyMessage="No players found"
            />

            {/* Pagination */}
            <Pagination page={page} total={total} limit={20} onChange={setPage} />

            {/* Detail panel */}
            {selectedId && (
                <PlayerDetailPanel
                    playerId={selectedId}
                    onClose={() => setSelectedId(null)}
                    onAction={refetch}
                    viewerRole={role}
                    workflow={playerWorkflows[selectedId] ?? createDefaultWorkflowState()}
                    onUpdateWorkflow={handleUpdateSelectedWorkflow}
                />
            )}

            {/* Confirm delete */}
            <ConfirmDialog
                open={!!deleteTarget}
                title="Delete Player"
                message={`Permanently delete "${deleteTarget?.email}"?`}
                confirmLabel="Delete"
                onConfirm={() => deleteTarget && handleDelete(deleteTarget)}
                onCancel={() => setDeleteTarget(null)}
                loading={actionLoading}
            />
        </div>
    );
}

// ── Sub-components ────────────────────────────────────────────────────────────

function StatBox({ label, value, icon }: { label: string; value: string; icon: string }) {
    return (
        <div style={{
            background: 'var(--color-surface2)',
            borderRadius: 12,
            padding: '12px 14px',
            border: '1px solid var(--color-border)',
            display: 'flex',
            flexDirection: 'column',
            gap: 4,
        }}>
            <span style={{ fontSize: 18 }}>{icon}</span>
            <span style={{ fontSize: 16, fontWeight: 900, color: 'var(--color-text)' }}>{value}</span>
            <span style={{ fontSize: 10, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '0.8px' }}>{label}</span>
        </div>
    );
}

function InfoRow({ label, value }: { label: string; value: string }) {
    return (
        <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: '1px solid var(--color-border)', fontSize: 12 }}>
            <span style={{ color: 'var(--color-text-muted)' }}>{label}</span>
            <span style={{ color: 'var(--color-text)', fontWeight: 600 }}>{value}</span>
        </div>
    );
}

function StatusBadge({ label, subtle = false }: { label: string; subtle?: boolean }) {
    const lower = label.toLowerCase();
    let tone: React.CSSProperties = {
        background: 'rgba(29,99,255,0.14)',
        border: '1px solid rgba(29,99,255,0.35)',
        color: '#8bc3ff',
    };

    if (lower.includes('verified') || lower.includes('approved')) {
        tone = {
            background: 'rgba(76,217,100,0.15)',
            border: '1px solid rgba(76,217,100,0.35)',
            color: '#7be18f',
        };
    }

    if (lower.includes('rejected') || lower.includes('cancelled')) {
        tone = {
            background: 'rgba(255,77,79,0.12)',
            border: '1px solid rgba(255,77,79,0.35)',
            color: '#ff8f91',
        };
    }

    if (lower.includes('pending')) {
        tone = {
            background: 'rgba(253,176,34,0.12)',
            border: '1px solid rgba(253,176,34,0.35)',
            color: '#ffd88a',
        };
    }

    return (
        <span
            style={{
                borderRadius: 999,
                padding: subtle ? '3px 9px' : '4px 10px',
                fontSize: subtle ? 10 : 11,
                fontWeight: 700,
                textTransform: 'uppercase',
                letterSpacing: '0.7px',
                ...tone,
            }}
        >
            {label.split('_').join(' ')}
        </span>
    );
}

// ── Styles ─────────────────────────────────────────────────────────────────

const panelOverlay: React.CSSProperties = {
    position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.55)', zIndex: 900, display: 'flex', justifyContent: 'flex-end',
};

const panelDrawer: React.CSSProperties = {
    width: 480,
    maxWidth: '95vw',
    height: '100vh',
    background: 'var(--color-surface)',
    borderLeft: '1px solid var(--color-border)',
    padding: 28,
    overflowY: 'auto',
    boxShadow: '-8px 0 40px rgba(0,0,0,0.4)',
};

const selectStyle: React.CSSProperties = {
    background: 'var(--color-surface2)',
    border: '1px solid rgba(39,49,74,0.9)',
    borderRadius: 'var(--radius-input)',
    color: 'var(--color-text)',
    padding: '10px 14px',
    fontSize: 13,
    cursor: 'pointer',
};

const avatarStyle: React.CSSProperties = {
    width: 34,
    height: 34,
    borderRadius: '50%',
    background: 'linear-gradient(135deg, var(--color-primary), var(--color-accent))',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontWeight: 900,
    fontSize: 14,
    flexShrink: 0,
};

const sectionTitle: React.CSSProperties = {
    fontSize: 10,
    fontWeight: 800,
    color: 'var(--color-text-muted)',
    textTransform: 'uppercase',
    letterSpacing: '1.4px',
    marginBottom: 12,
};

const workflowBadgeRowStyle: React.CSSProperties = {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 8,
};

const workflowHintStyle: React.CSSProperties = {
    marginTop: 10,
    fontSize: 12,
    color: 'var(--color-text-muted)',
};

const resourceBoxStyle: React.CSSProperties = {
    border: '1px solid var(--color-border)',
    borderRadius: 12,
    background: 'var(--color-surface2)',
    padding: 10,
};

const resourceTitleStyle: React.CSSProperties = {
    fontSize: 12,
    fontWeight: 800,
    color: 'var(--color-text)',
    marginBottom: 6,
};

const resourceItemStyle: React.CSSProperties = {
    fontSize: 12,
    color: 'var(--color-text-muted)',
    marginBottom: 4,
};

const docCardStyle: React.CSSProperties = {
    border: '1px solid var(--color-border)',
    borderRadius: 10,
    padding: 8,
    background: 'var(--color-surface2)',
    minHeight: 150,
};

const docTitleStyle: React.CSSProperties = {
    fontSize: 11,
    fontWeight: 800,
    color: 'var(--color-text)',
    marginBottom: 6,
    textTransform: 'uppercase',
    letterSpacing: '0.8px',
};

const docHintStyle: React.CSSProperties = {
    fontSize: 12,
    color: 'var(--color-text-muted)',
};

const docImageStyle: React.CSSProperties = {
    width: '100%',
    height: 110,
    objectFit: 'cover',
    borderRadius: 8,
    border: '1px solid var(--color-border)',
};

const reportInputStyle: React.CSSProperties = {
    width: '100%',
    minHeight: 90,
    resize: 'vertical',
    background: 'var(--color-surface2)',
    border: '1px solid var(--color-border)',
    borderRadius: 10,
    color: 'var(--color-text)',
    padding: '10px 12px',
    fontSize: 12,
};

const inputLabelStyle: React.CSSProperties = {
    display: 'block',
    fontSize: 10,
    fontWeight: 800,
    color: 'var(--color-text-muted)',
    textTransform: 'uppercase',
    letterSpacing: '0.9px',
    marginBottom: 6,
};

const contractInputStyle: React.CSSProperties = {
    width: '100%',
    background: 'var(--color-surface2)',
    border: '1px solid var(--color-border)',
    borderRadius: 10,
    color: 'var(--color-text)',
    padding: '10px 12px',
    fontSize: 13,
};
