import React from 'react';
import { memberColor, memberAvatar, type MemberAppearance } from '../lib/members';

interface Props extends MemberAppearance { metadata?: string; }

export default function MemberIdentity({ name = '匿名用户', avatar, frame, badge, color, metadata }: Props) {
  return (
    <div className="member-identity">
      <img
        className="member-avatar"
        style={{ '--member-frame': memberColor(frame) || '#f0eafa' } as React.CSSProperties}
        src={memberAvatar(avatar)}
        alt={`${name}的头像`}
        width={42}
        height={42}
        onError={(event) => {
          const img = event.currentTarget;
          img.onerror = null;
          img.src = '/brand/bllii-symbol.svg';
        }}
      />
      <div className="member-identity__details">
        <span className="member-name">
          <strong style={memberColor(color) ? { color: memberColor(color) } : undefined}>{name}</strong>
          {badge ? <span className="member-badge" aria-label={`铭牌：${badge}`}>{badge}</span> : null}
        </span>
        {metadata ? <small className="member-metadata">{metadata}</small> : null}
      </div>
    </div>
  );
}
