import React, { useEffect } from 'react';
import BrandDialog from './BrandDialog';
import { initDialogs } from '../lib/dialogs';

export default function ConfirmDialog() {
  useEffect(() => {
    initDialogs();
  }, []);

  return (
    <BrandDialog
      id="site-confirm"
      title="确认操作"
      descriptionId="site-confirm-description"
      className="brand-dialog--confirm"
      footer={
        <>
          <button type="button" className="brand-outline" data-confirm-cancel>
            取消
          </button>
          <button type="button" className="brand-button" data-confirm-accept>
            确认
          </button>
        </>
      }
    >
      <p id="site-confirm-description" data-confirm-description></p>
    </BrandDialog>
  );
}
