import React, { FC } from 'react';

import SectionWithSwitch from '@kubevirt-utils/components/SectionWithSwitch/SectionWithSwitch';
import { useKubevirtTranslation } from '@kubevirt-utils/hooks/useKubevirtTranslation';
import { CLUSTER_TAB_IDS } from '@overview/SettingsTab/search/constants';

import ExpandSection from '../../../../ExpandSection/ExpandSection';

import useAdvancedCDROMFeatureFlag from './hooks/useAdvancedCDROMFeatureFlag';
import AdvancedCDROMPopoverContent from './AdvancedCDROMPopoverContent';

type AdvancedCDROMFeaturesProps = {
  newBadge?: boolean;
};

const AdvancedCDROMFeatures: FC<AdvancedCDROMFeaturesProps> = ({ newBadge }) => {
  const { t } = useKubevirtTranslation();
  const { canEdit, featureEnabled, loading, toggleFeature } = useAdvancedCDROMFeatureFlag();

  return (
    <ExpandSection
      searchItemId={CLUSTER_TAB_IDS.advancedCDROMFeatures}
      toggleText={t('Advanced CD-ROM features')}
    >
      <SectionWithSwitch
        dataTestID="advanced-cdrom-features"
        helpTextIconContent={<AdvancedCDROMPopoverContent />}
        isDisabled={!canEdit}
        isLoading={loading}
        newBadge={newBadge}
        switchIsOn={featureEnabled}
        title={t('Enable advanced CD-ROM features')}
        turnOnSwitch={toggleFeature}
      />
    </ExpandSection>
  );
};

export default AdvancedCDROMFeatures;
